// device events: only "add" is a new device, a node already in the list is not added again (matron/src/device/device_dedupe.h; KNOWN-ISSUES 31). run from run_all.sh
#define DOCTEST_CONFIG_IMPLEMENT_WITH_MAIN
#include "doctest/doctest.h"

#include "device/device_dedupe.h"

TEST_CASE("only add is a new device") {
    CHECK(dev_action_is_add("add"));
    for (const char *a : {"change", "bind", "unbind", "online", "offline", "move", "remove", "", "ADD", "added"}) {
        CHECK_FALSE(dev_action_is_add(a));
    }
    CHECK_FALSE(dev_action_is_add(nullptr));
    CHECK(dev_action_is_remove("remove"));
    CHECK_FALSE(dev_action_is_remove("change"));
    CHECK_FALSE(dev_action_is_remove(nullptr));
}

TEST_CASE("the same node is a duplicate") {
    CHECK(dev_same_node("/dev/ttyACM0", "/dev/ttyACM0"));
    CHECK_FALSE(dev_same_node("/dev/ttyACM0", "/dev/ttyACM1"));
    CHECK_FALSE(dev_same_node("/dev/ttyACM0", "/dev/ttyUSB0"));
    CHECK_FALSE(dev_same_node(nullptr, "/dev/ttyACM0"));
    CHECK_FALSE(dev_same_node("/dev/ttyACM0", nullptr));
    CHECK_FALSE(dev_same_node("", ""));
}

TEST_CASE("one physical grid has one serial and one name") {
    CHECK(dev_same_monome("m1000218", "monome", "m1000218", "monome"));
    CHECK_FALSE(dev_same_monome("m1000218", "monome", "m1000219", "monome"));
    CHECK_FALSE(dev_same_monome("m1000218", "monome", "m1000218", "monome arc"));
    CHECK_FALSE(dev_same_monome("", "monome", "", "monome")); // no serial: cannot tell
    CHECK_FALSE(dev_same_monome(nullptr, "monome", "m1", "monome"));
}
