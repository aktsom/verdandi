// NamAmp: a SuperCollider UGen that plays Neural Amp Modeler captures (.nam), for scripts such as princeton. Verdandi's own implementation of the interface
// that those scripts use (the class `NamAmp.ar(in, active)` and the plug-in command `/cmd namLoad <path> <gain>`), on NeuralAmpModelerCore (MIT), Eigen (MPL-2.0)
// and nlohmann/json (MIT). Copyright the Verdandi authors, GPL-3.0-or-later. docs/port/namamp.md.
//
//   NamAmp.ar(in, active): one audio input, one audio output; active <= 0.5 gives silence (and no processing)
//   /cmd namLoad <path> <gain>: loads the model off the audio thread, then hands it to the unit. gain is a linear factor on the output; it is multiplied with
//       the setting namamp_gain (audio.conf, in dB: the environment variable NORNS_NAMAMP_GAIN) that the launcher passes on, read at every load
//   one model at a time, owned by one unit (the scripts use one instance): a second unit says so once and stays silent
//   the model is never freed on the audio thread: a replaced model waits in a slot that the next load (not the audio thread) empties
#include "SC_PlugIn.hpp"

#include <atomic>
#include <cmath>
#include <cstdlib>
#include <filesystem>
#include <memory>
#include <string>
#include <vector>

#include "NAM/get_dsp.h"

static InterfaceTable *ft;

namespace {

struct Model {
    std::unique_ptr<nam::DSP> dsp;
    float gain = 1.0f;
};

std::atomic<Model *> g_pending{nullptr};   // a loaded model that no unit took yet
std::atomic<Model *> g_retired{nullptr};   // a replaced model, emptied by the next load
std::atomic<int> g_owner_claimed{0};       // 1: a unit owns the model

const int MAX_BLOCK = 1024;

float setting_gain_db() {
    const char *v = getenv("NORNS_NAMAMP_GAIN");
    if (v == nullptr || v[0] == '\0') {
        return 0.0f;
    }
    char *end = nullptr;
    double d = strtod(v, &end);
    if (end == v) {
        return 0.0f;
    }
    if (d > 24.0) d = 24.0;
    if (d < -48.0) d = -48.0;
    return (float)d;
}

struct NamAmp : public SCUnit {
    Model *model = nullptr;
    bool owns = false;
    bool warned = false;
    std::vector<NAM_SAMPLE> inbuf, outbuf;

    NamAmp() {
        inbuf.assign(MAX_BLOCK, 0);
        outbuf.assign(MAX_BLOCK, 0);
        mCalcFunc = make_calc_function<NamAmp, &NamAmp::next>();
        next(1);
    }
    ~NamAmp() {
        if (model != nullptr) {
            // not freed here (this may be the audio thread): the next load empties the slot
            Model *old = g_retired.exchange(model);
            (void)old; // a second retired model is a leak until the process ends: it happens only when a node is freed twice between two loads
        }
        if (owns) {
            g_owner_claimed.store(0);
        }
    }

    void next(int n) {
        Model *p = g_pending.load();
        if (p != nullptr && (owns || g_owner_claimed.load() == 0)) {
            if (g_pending.compare_exchange_strong(p, nullptr)) {
                Model *old = model;
                model = p;
                if (!owns) {
                    owns = true;
                    g_owner_claimed.store(1);
                }
                if (old != nullptr) {
                    g_retired.exchange(old);
                }
            }
        } else if (p != nullptr && !owns && !warned) {
            warned = true;
            Print("NamAmp: only one instance can play a model; this one stays silent\n");
        }
        const float *src = in(0);
        float *dst = out(0);
        const bool active = in0(1) > 0.5f;
        if (model == nullptr || !active || n > MAX_BLOCK) {
            for (int i = 0; i < n; i++) {
                dst[i] = 0.f;
            }
            return;
        }
        for (int i = 0; i < n; i++) {
            inbuf[i] = (NAM_SAMPLE)src[i];
        }
        NAM_SAMPLE *ip = inbuf.data();
        NAM_SAMPLE *op = outbuf.data();
        model->dsp->process(&ip, &op, n);
        const float g = model->gain;
        for (int i = 0; i < n; i++) {
            float v = (float)op[i] * g;
            dst[i] = std::isfinite(v) ? v : 0.f;
        }
    }
};

struct LoadData {
    std::string path;
    float gain;
    Model *model;
    double sr;
};

bool loadStage2(World *, void *data) { // not the audio thread
    LoadData *d = (LoadData *)data;
    try {
        std::unique_ptr<Model> m(new Model());
        m->dsp = nam::get_dsp(std::filesystem::path(d->path));
        m->dsp->Reset(d->sr, MAX_BLOCK);
        m->gain = d->gain;
        double expected = m->dsp->GetExpectedSampleRate();
        if (expected > 0 && std::fabs(expected - d->sr) > 1.0 && !m->dsp->SupportsArbitrarySampleRate()) {
            Print("NamAmp: %s was captured at %.0f Hz and the server runs at %.0f Hz: it will sound off\n", d->path.c_str(), expected, d->sr);
        }
        d->model = m.release();
    } catch (const std::exception &e) {
        Print("NamAmp: failed to load %s: %s\n", d->path.c_str(), e.what());
        d->model = nullptr;
    }
    return true;
}

bool loadStage3(World *, void *data) { // not the audio thread: the model goes to the unit
    LoadData *d = (LoadData *)data;
    if (d->model != nullptr) {
        delete g_retired.exchange(nullptr);
        Model *prev = g_pending.exchange(d->model);
        delete prev;
        Print("NamAmp: loaded %s (gain %.2f)\n", d->path.c_str(), d->model->gain);
        d->model = nullptr;
    }
    return true;
}

bool loadStage4(World *, void *) { return false; }

void loadCleanup(World *, void *data) { delete (LoadData *)data; }

void cmdLoad(World *world, void *, struct sc_msg_iter *args, void *replyAddr) {
    LoadData *d = new LoadData;
    d->path = args->gets("");
    float factor = args->getf(1.0f);
    d->gain = factor * std::pow(10.0f, setting_gain_db() / 20.0f);
    d->model = nullptr;
    d->sr = world->mSampleRate;
    DoAsynchronousCommand(world, replyAddr, "namLoad", d, loadStage2, loadStage3, loadStage4, loadCleanup, 0, nullptr);
}

} // namespace

PluginLoad(NamAmp) {
    ft = inTable;
    registerUnit<NamAmp>(ft, "NamAmp");
    DefinePlugInCmd("namLoad", cmdLoad, nullptr);
}
