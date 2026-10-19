// NornsAU.mm
//
// the norns AUv3 (music effect: stereo audio in/out + MIDI in). it carries the DAW's audio
// to norns.app and back (auv3_bridge, see bridge_protocol.h) and passes the DAW's MIDI on.
// norns itself keeps running in its own window; while the plugin renders, norns hears the
// DAW instead of the audio interface and plays into the DAW instead of the speakers.
//
// render thread: lock-free rings only. a network thread sends fixed blocks over UDP to
// 127.0.0.1 and collects the answers. without norns the plugin passes audio through.

#import <AudioToolbox/AudioToolbox.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreAudioKit/CoreAudioKit.h>

#include <arpa/inet.h>
#include <atomic>
#include <chrono>
#include <netinet/in.h>
#include <string.h>
#include <sys/socket.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "bridge_protocol.h"

namespace {

// single producer / single consumer ring of stereo frames
class FrameRing {
  public:
    explicit FrameRing(size_t frames) : buf_(frames * NB_CHANNELS), cap_(frames) {}
    size_t available() const { return w_.load(std::memory_order_acquire) - r_.load(std::memory_order_acquire); }
    size_t space() const { return cap_ - available(); }
    void push(const float *l, const float *r, size_t n) {
        size_t w = w_.load(std::memory_order_relaxed);
        for (size_t i = 0; i < n; i++, w++) {
            size_t k = (w % cap_) * NB_CHANNELS;
            buf_[k] = l[i];
            buf_[k + 1] = r[i];
        }
        w_.store(w, std::memory_order_release);
    }
    void pop(float *l, float *r, size_t n) {
        size_t rd = r_.load(std::memory_order_relaxed);
        for (size_t i = 0; i < n; i++, rd++) {
            size_t k = (rd % cap_) * NB_CHANNELS;
            l[i] = buf_[k];
            r[i] = buf_[k + 1];
        }
        r_.store(rd, std::memory_order_release);
    }
    void clear() { r_.store(w_.load()); }

  private:
    std::vector<float> buf_;
    size_t cap_;
    std::atomic<size_t> r_{0}, w_{0};
};

// single producer / single consumer byte ring for MIDI
class ByteRing {
  public:
    size_t available() const { return w_.load(std::memory_order_acquire) - r_.load(std::memory_order_acquire); }
    void push(const uint8_t *b, size_t n) {
        if (sizeof(buf_) - available() < n) {
            return;
        }
        size_t w = w_.load(std::memory_order_relaxed);
        for (size_t i = 0; i < n; i++, w++) {
            buf_[w % sizeof(buf_)] = b[i];
        }
        w_.store(w, std::memory_order_release);
    }
    size_t pop(uint8_t *out, size_t max) {
        size_t n = available() < max ? available() : max;
        size_t rd = r_.load(std::memory_order_relaxed);
        for (size_t i = 0; i < n; i++, rd++) {
            out[i] = buf_[rd % sizeof(buf_)];
        }
        r_.store(rd, std::memory_order_release);
        return n;
    }

  private:
    uint8_t buf_[8192];
    std::atomic<size_t> r_{0}, w_{0};
};

double now_s() {
    return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

class Bridge {
  public:
    static constexpr size_t kPrime = 2 * NB_BLOCK; // output buffered before playing

    Bridge() : toNorns_(16384), fromNorns_(16384) {}
    ~Bridge() { stop(); }

    void start(double sampleRate) {
        stop();
        rate_ = (uint32_t)sampleRate;
        toNorns_.clear();
        fromNorns_.clear();
        primed_ = false;
        sock_ = socket(AF_INET, SOCK_DGRAM, 0);
        if (sock_ < 0) {
            return;
        }
        sockaddr_in addr = {};
        addr.sin_family = AF_INET;
        addr.sin_port = htons(NB_PORT);
        addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
        connect(sock_, (sockaddr *)&addr, sizeof(addr));
        timeval tv = {0, 1000};
        setsockopt(sock_, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
        running_ = true;
        thread_ = std::thread([this] { loop(); });
    }

    void stop() {
        if (!running_) {
            return;
        }
        running_ = false;
        thread_.join();
        nb_header_t h = {NB_MAGIC, NB_BYE, 0, 0, rate_};
        send(sock_, &h, sizeof(h), 0);
        close(sock_);
        sock_ = -1;
    }

    bool connected() const { return now_s() - lastReply_.load() < 0.5; }

    // render thread
    void midi(const uint8_t *bytes, size_t n) { midi_.push(bytes, n); }

    void process(const float *inL, const float *inR, float *outL, float *outR, size_t n) {
        if (toNorns_.space() >= n) {
            toNorns_.push(inL, inR, n);
        }
        if (!connected()) {
            // no norns: stay transparent
            if (outL != inL) memcpy(outL, inL, n * sizeof(float));
            if (outR != inR) memcpy(outR, inR, n * sizeof(float));
            primed_ = false;
            return;
        }
        if (!primed_ && fromNorns_.available() >= kPrime) {
            primed_ = true;
        }
        if (primed_ && fromNorns_.available() >= n) {
            fromNorns_.pop(outL, outR, n);
        } else {
            memset(outL, 0, n * sizeof(float));
            memset(outR, 0, n * sizeof(float));
            primed_ = false;
        }
    }

  private:
    void loop() {
        uint8_t pkt[NB_MAX_PACKET];
        float l[NB_BLOCK], r[NB_BLOCK];
        uint32_t seq = 0;
        while (running_) {
            while (toNorns_.available() >= NB_BLOCK) {
                toNorns_.pop(l, r, NB_BLOCK);
                nb_header_t h = {NB_MAGIC, NB_AUDIO, NB_BLOCK, seq++, rate_};
                memcpy(pkt, &h, sizeof(h));
                memcpy(pkt + sizeof(h), l, sizeof(l));
                memcpy(pkt + sizeof(h) + sizeof(l), r, sizeof(r));
                send(sock_, pkt, sizeof(h) + NB_AUDIO_BYTES(NB_BLOCK), 0);
            }
            size_t m = midi_.pop(pkt + sizeof(nb_header_t), NB_MAX_MIDI);
            if (m > 0) {
                nb_header_t h = {NB_MAGIC, NB_MIDI, (uint16_t)m, seq, rate_};
                memcpy(pkt, &h, sizeof(h));
                send(sock_, pkt, sizeof(h) + m, 0);
            }
            ssize_t got = recv(sock_, pkt, sizeof(pkt), 0);
            if (got == (ssize_t)(sizeof(nb_header_t) + NB_AUDIO_BYTES(NB_BLOCK))) {
                nb_header_t h;
                memcpy(&h, pkt, sizeof(h));
                if (h.magic == NB_MAGIC && h.type == NB_AUDIO && h.frames == NB_BLOCK) {
                    memcpy(l, pkt + sizeof(h), sizeof(l));
                    memcpy(r, pkt + sizeof(h) + sizeof(l), sizeof(r));
                    if (fromNorns_.space() >= NB_BLOCK) {
                        fromNorns_.push(l, r, NB_BLOCK);
                    }
                    lastReply_ = now_s();
                }
            }
        }
    }

    FrameRing toNorns_, fromNorns_;
    ByteRing midi_;
    std::thread thread_;
    std::atomic<bool> running_{false};
    std::atomic<double> lastReply_{0};
    bool primed_ = false; // render thread only
    int sock_ = -1;
    uint32_t rate_ = 48000;
};

} // namespace

@interface NornsAudioUnit : AUAudioUnit
@property(nonatomic, readonly) BOOL nornsConnected;
@end

@implementation NornsAudioUnit {
    AUAudioUnitBus *_inputBus;
    AUAudioUnitBus *_outputBus;
    AUAudioUnitBusArray *_inputBusArray;
    AUAudioUnitBusArray *_outputBusArray;
    AVAudioPCMBuffer *_inputBuffer;
    Bridge *_bridge;
}

- (instancetype)initWithComponentDescription:(AudioComponentDescription)componentDescription
                                     options:(AudioComponentInstantiationOptions)options
                                       error:(NSError **)outError {
    self = [super initWithComponentDescription:componentDescription options:options error:outError];
    if (self == nil) {
        return nil;
    }
    AVAudioFormat *format = [[AVAudioFormat alloc] initStandardFormatWithSampleRate:48000 channels:2];
    _inputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
    _outputBus = [[AUAudioUnitBus alloc] initWithFormat:format error:nil];
    _inputBus.maximumChannelCount = 2;
    _outputBus.maximumChannelCount = 2;
    _inputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                            busType:AUAudioUnitBusTypeInput
                                                             busses:@[ _inputBus ]];
    _outputBusArray = [[AUAudioUnitBusArray alloc] initWithAudioUnit:self
                                                             busType:AUAudioUnitBusTypeOutput
                                                              busses:@[ _outputBus ]];
    self.maximumFramesToRender = 4096;
    self.parameterTree = [AUParameterTree createTreeWithChildren:@[]];
    _bridge = new Bridge();
    return self;
}

- (void)dealloc {
    delete _bridge;
}

- (AUAudioUnitBusArray *)inputBusses {
    return _inputBusArray;
}

- (AUAudioUnitBusArray *)outputBusses {
    return _outputBusArray;
}

// (in, out) pairs: mono, stereo, mono into stereo
- (NSArray<NSNumber *> *)channelCapabilities {
    return @[ @1, @1, @2, @2, @1, @2 ];
}

- (NSTimeInterval)latency {
    return (NB_BLOCK + Bridge::kPrime) / _outputBus.format.sampleRate;
}

- (BOOL)nornsConnected {
    return _bridge->connected();
}

- (BOOL)allocateRenderResourcesAndReturnError:(NSError **)outError {
    if (![super allocateRenderResourcesAndReturnError:outError]) {
        return NO;
    }
    _inputBuffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:_inputBus.format frameCapacity:self.maximumFramesToRender];
    _bridge->start(_outputBus.format.sampleRate);
    return YES;
}

- (void)deallocateRenderResources {
    _bridge->stop();
    _inputBuffer = nil;
    [super deallocateRenderResources];
}

- (AUInternalRenderBlock)internalRenderBlock {
    Bridge *bridge = _bridge;
    __block AVAudioPCMBuffer *inputBuffer = nil;
    __unsafe_unretained NornsAudioUnit *weakSelf = self;
    return ^AUAudioUnitStatus(AudioUnitRenderActionFlags *actionFlags, const AudioTimeStamp *timestamp,
                              AVAudioFrameCount frameCount, NSInteger outputBusNumber, AudioBufferList *outputData,
                              const AURenderEvent *events, AURenderPullInputBlock pullInputBlock) {
        (void)outputBusNumber;
        if (inputBuffer == nil) {
            inputBuffer = weakSelf->_inputBuffer;
        }
        for (const AURenderEvent *ev = events; ev != NULL; ev = ev->head.next) {
            if (ev->head.eventType == AURenderEventMIDI) {
                bridge->midi(ev->MIDI.data, ev->MIDI.length);
            }
        }

        AudioBufferList *in = inputBuffer.mutableAudioBufferList;
        for (UInt32 i = 0; i < in->mNumberBuffers; i++) {
            in->mBuffers[i].mDataByteSize = frameCount * sizeof(float);
        }
        if (pullInputBlock == nil || pullInputBlock(actionFlags, timestamp, frameCount, 0, in) != noErr) {
            for (UInt32 i = 0; i < in->mNumberBuffers; i++) {
                memset(in->mBuffers[i].mData, 0, frameCount * sizeof(float));
            }
        }
        const float *inL = (const float *)in->mBuffers[0].mData;
        const float *inR = in->mNumberBuffers > 1 ? (const float *)in->mBuffers[1].mData : inL;

        // hosts may hand us null output buffers: render into our own
        for (UInt32 i = 0; i < outputData->mNumberBuffers; i++) {
            if (outputData->mBuffers[i].mData == NULL) {
                outputData->mBuffers[i].mData = in->mBuffers[i < in->mNumberBuffers ? i : 0].mData;
            }
            outputData->mBuffers[i].mDataByteSize = frameCount * sizeof(float);
        }
        float *outL = (float *)outputData->mBuffers[0].mData;
        float *outR = outputData->mNumberBuffers > 1 ? (float *)outputData->mBuffers[1].mData : outL;
        if (outR == outL) {
            // mono out: render the right channel into scratch space (the input's spare buffer)
            static float scratch[4096];
            outR = scratch;
        }
        bridge->process(inL, inR, outL, outR, frameCount);
        return noErr;
    };
}

@end

@interface NornsViewController : AUViewController <AUAudioUnitFactory>
@end

@implementation NornsViewController {
    NornsAudioUnit *_unit;
    NSTextField *_status;
    NSTimer *_timer;
}

- (AUAudioUnit *)createAudioUnitWithComponentDescription:(AudioComponentDescription)desc error:(NSError **)error {
    _unit = [[NornsAudioUnit alloc] initWithComponentDescription:desc error:error];
    return _unit;
}

- (void)loadView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 440, 150)];
    view.wantsLayer = YES;
    view.layer.backgroundColor = NSColor.blackColor.CGColor;

    NSTextField *title = [NSTextField labelWithString:@"norns"];
    title.font = [NSFont monospacedSystemFontOfSize:28 weight:NSFontWeightBold];
    title.textColor = NSColor.whiteColor;
    title.frame = NSMakeRect(20, 92, 400, 40);
    [view addSubview:title];

    _status = [NSTextField wrappingLabelWithString:@""];
    _status.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
    _status.textColor = [NSColor colorWithWhite:0.75 alpha:1];
    _status.frame = NSMakeRect(20, 16, 400, 70);
    [view addSubview:_status];

    self.view = view;
    self.preferredContentSize = view.frame.size;
    [self refresh];
    __unsafe_unretained NornsViewController *weakSelf = self;
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.5 repeats:YES block:^(NSTimer *t) { [weakSelf refresh]; }];
}

- (void)viewDidDisappear {
    [super viewDidDisappear];
    [_timer invalidate];
    _timer = nil;
}

- (void)refresh {
    if (_unit != nil && _unit.nornsConnected) {
        _status.stringValue = @"connected. play norns in its window; it hears this track and plays into it. "
                              @"MIDI from this track arrives as the device \"norns AUv3\".";
    } else {
        _status.stringValue = @"norns is not running: audio passes through unchanged. "
                              @"start norns.app, then press play.";
    }
}

@end
