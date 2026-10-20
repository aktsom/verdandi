/*
 * mac_menu.m: see mac_menu.h. manual retain/release (not ARC): everything made here
 * lives as long as the app.
 */

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <objc/runtime.h>

#include "app_audio.h"
#include "mac_menu.h"

static void (*item_cb)(int id) = NULL;
static void (*import_cb)(const char *path, int mode) = NULL;
static void (*note_cb)(const char *text) = NULL;

static void note(NSString *text) {
    if (note_cb != NULL) {
        note_cb(text.UTF8String);
    }
}

#define APP_INPUT_MAX 40

@interface NornsMenuTarget : NSObject <NSMenuDelegate>
- (void)act:(NSMenuItem *)item;
- (void)pickApp:(NSMenuItem *)item;
@end

@implementation NornsMenuTarget
- (void)act:(NSMenuItem *)item {
    if (item.tag == MAC_MENU_IMPORT) {
        mac_menu_choose_import();
    } else if (item_cb != NULL) {
        item_cb((int)item.tag);
    }
}

// Devices > Audio Input from App: the running apps, made fresh each time it opens
- (void)menuNeedsUpdate:(NSMenu *)menu {
    [menu removeAllItems];
    const char *cur = app_audio_current();
    NSMenuItem *none = [menu addItemWithTitle:@"None" action:@selector(pickApp:) keyEquivalent:@""];
    none.target = self;
    none.representedObject = nil;
    none.state = cur == NULL ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:[NSMenuItem separatorItem]];
    app_audio_app_t apps[APP_INPUT_MAX];
    int n = app_audio_list(apps, APP_INPUT_MAX);
    for (int i = 0; i < n; i++) {
        NSString *title = [NSString stringWithUTF8String:apps[i].name];
        if (apps[i].playing) {
            title = [title stringByAppendingString:@"  (playing)"];
        }
        NSMenuItem *it = [menu addItemWithTitle:title action:@selector(pickApp:) keyEquivalent:@""];
        it.target = self;
        it.representedObject = @{@"bundle" : @(apps[i].bundle), @"name" : @(apps[i].name)};
        it.state = cur != NULL && strcmp(cur, apps[i].bundle) == 0 ? NSControlStateValueOn : NSControlStateValueOff;
        NSRunningApplication *ra =
            [NSRunningApplication runningApplicationsWithBundleIdentifier:@(apps[i].bundle)].firstObject;
        if (ra.icon != nil) {
            NSImage *icon = [[ra.icon copy] autorelease];
            icon.size = NSMakeSize(16, 16);
            it.image = icon;
        }
    }
    if (n == 0) {
        NSMenuItem *it = [menu addItemWithTitle:@"no other apps running" action:nil keyEquivalent:@""];
        it.enabled = NO;
    }
}

static int picks = 0;

- (void)pickApp:(NSMenuItem *)item {
    NSDictionary *app = item.representedObject;
    int pick = ++picks;
    if (app == nil) {
        if (app_audio_current() != NULL) {
            app_audio_select(NULL);
            note(@"app input off");
        }
        return;
    }
    if (app_audio_select([app[@"bundle"] UTF8String])) {
        note([NSString stringWithFormat:@"input from %@: it plays through norns now", app[@"name"]]);
        // the helper ends at once when it cannot tap here (unless another pick came since)
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{
          if (pick == picks && app_audio_current() == NULL) {
              note(@"app input stopped (see norns.log)");
          }
        });
    } else {
        note(@"app input does not start (see norns.log)");
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

void mac_menu_install(void (*on_item)(int id), void (*on_import)(const char *path, int mode),
                      void (*on_note)(const char *text)) {
    item_cb = on_item;
    import_cb = on_import;
    note_cb = on_note;
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
    if (app_audio_available()) {
        [devices addItem:[NSMenuItem separatorItem]];
        NSMenuItem *from = [devices addItemWithTitle:@"Audio Input from App" action:nil keyEquivalent:@""];
        NSMenu *apps = [[NSMenu alloc] initWithTitle:@"Audio Input from App"];
        apps.delegate = target;
        from.submenu = apps;
        [apps release];
    }

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
      int mode = copy.state == NSControlStateValueOn ? MAC_IMPORT_COPY : MAC_IMPORT_LINK;
      for (NSURL *url in panel.URLs) {
          if (url.fileURL) {
              import_cb(url.path.fileSystemRepresentation, mode);
          }
      }
    }];
}

int mac_option_held(void) {
    return ([NSEvent modifierFlags] & NSEventModifierFlagOption) != 0;
}

//--- drops beyond the Finder's files
//
// SDL's window takes file URLs (and text). apps that drag something they write only when it
// is dropped (a file promise) or plain audio data get nothing from it: the SDL window class
// gets drop methods of ours that take those and leave the rest to SDL's.

// audio data on the pasteboard: the types norns can play (dust_import.c's list)
static NSArray<NSString *> *audio_data_types(void) {
    static NSArray *types = nil;
    if (types == nil) {
        NSMutableArray *t = [NSMutableArray array];
        for (NSString *ext in @[ @"wav", @"aiff", @"aifc", @"flac", @"ogg", @"mp3" ]) {
            UTType *u = [UTType typeWithFilenameExtension:ext];
            if (u != nil && ![t containsObject:u.identifier]) {
                [t addObject:u.identifier];
            }
        }
        types = [t retain];
    }
    return types;
}

static NSArray<NSString *> *extra_types(void) {
    return [[NSFilePromiseReceiver readableDraggedTypes] arrayByAddingObjectsFromArray:audio_data_types()];
}

static int has_files(NSPasteboard *pb) {
    return [pb canReadObjectForClasses:@[ [NSURL class] ] options:@{NSPasteboardURLReadingFileURLsOnlyKey : @YES}];
}

static int has_promise(NSPasteboard *pb) {
    return [pb canReadObjectForClasses:@[ [NSFilePromiseReceiver class] ] options:nil];
}

static NSString *audio_data_type(NSPasteboard *pb) {
    return [pb availableTypeFromArray:audio_data_types()];
}

// ours to take: no Finder file (SDL has those), but a promise or audio data
static int ours(id<NSDraggingInfo> info) {
    NSPasteboard *pb = [info draggingPasteboard];
    return !has_files(pb) && (has_promise(pb) || audio_data_type(pb) != nil);
}

// a folder of its own for each drop: the app names the files
static NSURL *drop_folder(void) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"norns-drops"];
    dir = [dir stringByAppendingPathComponent:[NSUUID UUID].UUIDString];
    if (![[NSFileManager defaultManager] createDirectoryAtPath:dir
                                   withIntermediateDirectories:YES
                                                    attributes:nil
                                                         error:NULL]) {
        return nil;
    }
    return [NSURL fileURLWithPath:dir isDirectory:YES];
}

static void take(NSURL *url) {
    char *path = strdup(url.path.fileSystemRepresentation);
    dispatch_async(dispatch_get_main_queue(), ^{
      if (import_cb != NULL) {
          import_cb(path, MAC_IMPORT_TAKE);
      }
      free(path);
    });
}

static BOOL take_drop(id<NSDraggingInfo> info) {
    static NSOperationQueue *queue = nil;
    if (queue == nil) {
        queue = [[NSOperationQueue alloc] init];
        queue.qualityOfService = NSQualityOfServiceUserInitiated;
    }
    NSPasteboard *pb = [info draggingPasteboard];
    NSURL *dir = drop_folder();
    if (dir == nil) {
        return NO;
    }
    NSArray *promises = [pb readObjectsForClasses:@[ [NSFilePromiseReceiver class] ] options:nil];
    if (promises.count > 0) {
        note(promises.count == 1 ? @"getting the file from the app" : @"getting the files from the app");
        for (NSFilePromiseReceiver *r in promises) {
            [r receivePromisedFilesAtDestination:dir
                                         options:@{}
                                  operationQueue:queue
                                          reader:^(NSURL *url, NSError *error) {
                                            if (error != nil) {
                                                fprintf(stderr, "mac_menu: promised file failed: %s\n",
                                                        error.localizedDescription.UTF8String);
                                                note(@"the app did not hand over the file");
                                                return;
                                            }
                                            take(url);
                                          }];
        }
        return YES;
    }
    NSString *type = audio_data_type(pb);
    NSData *data = type != nil ? [pb dataForType:type] : nil;
    NSString *ext = [UTType typeWithIdentifier:type].preferredFilenameExtension;
    if (data == nil || ext == nil) {
        return NO;
    }
    NSURL *file = [dir URLByAppendingPathComponent:[@"dropped audio" stringByAppendingPathExtension:ext]];
    if (![data writeToURL:file atomically:NO]) {
        return NO;
    }
    take(file);
    return YES;
}

// SDL's own methods, called for everything that is not ours
static IMP sdl_entered = NULL, sdl_updated = NULL, sdl_perform = NULL, sdl_register = NULL;
static Class adopted = Nil;

static NSDragOperation drop_entered(id self, SEL cmd, id<NSDraggingInfo> info) {
    if (ours(info)) {
        return NSDragOperationCopy;
    }
    IMP sdl = cmd == @selector(draggingUpdated:) ? sdl_updated : sdl_entered;
    return ((NSDragOperation(*)(id, SEL, id))sdl)(self, cmd, info);
}

static BOOL drop_perform(id self, SEL cmd, id<NSDraggingInfo> info) {
    if (ours(info)) {
        return take_drop(info);
    }
    BOOL ok = ((BOOL(*)(id, SEL, id))sdl_perform)(self, cmd, info);
    if (!has_files([info draggingPasteboard])) {
        // nothing norns can use: say so, and what the app offered (norns.log)
        fprintf(stderr, "mac_menu: drop without a file, types: %s\n",
                [[[info draggingPasteboard].types componentsJoinedByString:@", "] UTF8String]);
        note(@"nothing to import: the app dragged no audio file");
    }
    return ok;
}

// SDL registers its types again (drop events on and off): ours stay with them
static void drop_register(id self, SEL cmd, NSArray<NSString *> *types) {
    NSMutableArray *all = [NSMutableArray arrayWithArray:types];
    for (NSString *t in extra_types()) {
        if (![all containsObject:t]) {
            [all addObject:t];
        }
    }
    ((void (*)(id, SEL, id))sdl_register)(self, cmd, all);
}

// our method in place of SDL's (or the one it inherits); the old one is returned
static IMP replace(Class c, SEL sel, IMP ours_imp) {
    Method m = class_getInstanceMethod(c, sel);
    if (m == NULL) {
        return NULL;
    }
    IMP old = method_getImplementation(m);
    class_replaceMethod(c, sel, ours_imp, method_getTypeEncoding(m));
    return old;
}

static void adopt_class(Class c) {
    // SDL's drop handling is what this builds on: without it, leave the class alone
    if (class_getInstanceMethod(c, @selector(draggingEntered:)) == NULL ||
        class_getInstanceMethod(c, @selector(performDragOperation:)) == NULL) {
        return;
    }
    sdl_entered = replace(c, @selector(draggingEntered:), (IMP)drop_entered);
    // without its own, AppKit keeps what draggingEntered said
    if (class_getInstanceMethod(c, @selector(draggingUpdated:)) != NULL) {
        sdl_updated = replace(c, @selector(draggingUpdated:), (IMP)drop_entered);
    } else {
        sdl_updated = sdl_entered;
    }
    sdl_perform = replace(c, @selector(performDragOperation:), (IMP)drop_perform);
    sdl_register = replace(c, @selector(registerForDraggedTypes:), (IMP)drop_register);
    adopted = c;
}

void mac_drop_adopt_windows(void) {
    for (NSWindow *w in [NSApp windows]) {
        // the class it claims (KVO hides its own subclass)
        Class c = [w class];
        if (strstr(class_getName(c), "SDL") == NULL) {
            continue;
        }
        if (adopted == Nil) {
            adopt_class(c);
        }
        if (c != adopted) {
            continue;
        }
        // registered before we were there: SDL's types (files, text) once more, through
        // drop_register
        [w registerForDraggedTypes:@[ NSPasteboardTypeFileURL, NSPasteboardTypeString ]];
    }
}
