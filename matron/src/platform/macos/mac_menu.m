/*
 * mac_menu.m: see mac_menu.h. manual retain/release (not ARC): everything made here
 * lives as long as the app.
 */

#import <Cocoa/Cocoa.h>

#include "mac_menu.h"

static void (*item_cb)(int id) = NULL;
static void (*import_cb)(const char *path, int copy) = NULL;

@interface NornsMenuTarget : NSObject
- (void)act:(NSMenuItem *)item;
@end

@implementation NornsMenuTarget
- (void)act:(NSMenuItem *)item {
    if (item.tag == MAC_MENU_IMPORT) {
        mac_menu_choose_import();
    } else if (item_cb != NULL) {
        item_cb((int)item.tag);
    }
}
@end

static NornsMenuTarget *target = nil;
static NSMenuItem *gif_item = nil;

static NSMenuItem *add(NSMenu *menu, NSString *title, NSString *key, NSEventModifierFlags mods, int tag) {
    NSMenuItem *item = [menu addItemWithTitle:title action:@selector(act:) keyEquivalent:key];
    item.keyEquivalentModifierMask = mods;
    item.target = target;
    item.tag = tag;
    return item;
}

static void insert(NSMenu *bar, NSMenu *menu, NSInteger at) {
    NSMenuItem *top = [[NSMenuItem alloc] initWithTitle:menu.title action:nil keyEquivalent:@""];
    top.submenu = menu;
    [bar insertItem:top atIndex:at < bar.numberOfItems ? at : bar.numberOfItems];
    [top release];
}

void mac_menu_install(void (*on_item)(int id), void (*on_import)(const char *path, int copy)) {
    item_cb = on_item;
    import_cb = on_import;
    NSMenu *bar = [NSApp mainMenu];
    if (bar == nil || target != nil) {
        return;
    }
    target = [[NornsMenuTarget alloc] init];
    NSEventModifierFlags cmd = NSEventModifierFlagCommand;
    NSEventModifierFlags shift_cmd = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenu *file = [[NSMenu alloc] initWithTitle:@"File"];
    add(file, @"Import Audio or Script…", @"o", cmd, MAC_MENU_IMPORT);
    add(file, @"Show dust Folder", @"d", shift_cmd, MAC_MENU_DUST);
    add(file, @"Show Tape Recordings", @"t", shift_cmd, MAC_MENU_TAPE);
    [file addItem:[NSMenuItem separatorItem]];
    add(file, @"Save Screenshot", @"s", shift_cmd, MAC_MENU_SCREENSHOT);
    gif_item = [add(file, @"Record GIF", @"g", shift_cmd, MAC_MENU_GIF) retain];

    // the function keys belong to norns (lua/core/keyboard.lua): no key equivalents here
    NSMenu *devices = [[NSMenu alloc] initWithTitle:@"Devices"];
    add(devices, @"Grid  (F6)", @"", 0, MAC_MENU_GRID);
    add(devices, @"Keyboard  (F7)", @"", 0, MAC_MENU_KEYS);
    add(devices, @"Arc  (F8)", @"", 0, MAC_MENU_ARC);

    // after the app menu, before SDL's Window menu
    insert(bar, file, 1);
    insert(bar, devices, 2);
    [file release];
    [devices release];
}

void mac_menu_set_recording(int on) {
    gif_item.title = on ? @"Stop GIF Recording" : @"Record GIF";
}

void mac_menu_choose_import(void) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = YES;
    panel.message = @"Audio is linked from dust/audio/mac (it stays where it is); scripts are copied to dust/code.";
    panel.prompt = @"Import";
    NSButton *copy = [NSButton checkboxWithTitle:@"Copy audio into norns instead of linking it" target:nil action:nil];
    copy.state = NSControlStateValueOff;
    panel.accessoryView = copy;
    panel.accessoryViewDisclosed = YES;
    // not modal: the norns window keeps drawing while the panel is open
    [panel beginWithCompletionHandler:^(NSModalResponse result) {
      if (result != NSModalResponseOK || import_cb == NULL) {
          return;
      }
      int as_copy = copy.state == NSControlStateValueOn;
      for (NSURL *url in panel.URLs) {
          if (url.fileURL) {
              import_cb(url.path.fileSystemRepresentation, as_copy);
          }
      }
    }];
}

int mac_option_held(void) {
    return ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
}
