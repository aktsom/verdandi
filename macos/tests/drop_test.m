/*
 * drop_test.m: what the norns windows take when something is dropped on them
 * (matron/src/platform/macos/mac_menu.m on a real SDL window)
 *
 * P=matron/src/platform/macos
 * cc -c $P/mac_menu.m $P/app_audio.m -I $P && \
 * cc -fobjc-arc macos/tests/drop_test.m mac_menu.o app_audio.o -I $P $(pkg-config --cflags --libs sdl2) \
 *    -framework AppKit -framework CoreAudio -framework UniformTypeIdentifiers -o /tmp/drop_test && /tmp/drop_test
 *
 * without arguments it hands the window's drop methods made-up drags (a Finder file, wav data,
 * text). with --live it also starts itself as a drag source (another process, as an app is)
 * and drags a promised file onto the window with real mouse events: the mouse moves for a
 * second.
 */

#import <Cocoa/Cocoa.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <SDL.h>
#include <ApplicationServices/ApplicationServices.h>

#include "mac_menu.h"

static int failures = 0;

#define CHECK(cond, ...)                                                                                               \
    do {                                                                                                               \
        if (!(cond)) {                                                                                                 \
            failures++;                                                                                                \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                                                                \
            printf(__VA_ARGS__);                                                                                       \
            printf("\n");                                                                                              \
        }                                                                                                              \
    } while (0)

//--- what the window hands on

static NSMutableArray<NSDictionary *> *imports;
static NSMutableArray<NSString *> *notes;
static NSMutableArray<NSString *> *sdl_drops;

static void on_import(const char *path, int mode) {
    NSData *data = [NSData dataWithContentsOfFile:@(path)];
    [imports addObject:@{@"path" : @(path), @"mode" : @(mode), @"data" : data ?: [NSData data]}];
    // what norns' import does with a taken file once it is in dust
    if (mode == MAC_IMPORT_TAKE) {
        NSString *dir = [@(path) stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] removeItemAtPath:@(path) error:NULL];
        rmdir(dir.fileSystemRepresentation);
    }
}

static void on_note(const char *text) {
    [notes addObject:@(text)];
}

static void on_item(int id) {
    (void)id;
}

// SDL events and the main queue, for a while or until done() says so
static void pump(double seconds, BOOL (^done)(void)) {
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while ([until timeIntervalSinceNow] > 0 && (done == nil || !done())) {
        SDL_Event ev;
        while (SDL_PollEvent(&ev)) {
            if (ev.type == SDL_DROPFILE) {
                [sdl_drops addObject:@(ev.drop.file)];
                SDL_free(ev.drop.file);
            }
        }
        [[NSRunLoop mainRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
    }
}

//--- a made-up drag: just what a drop destination asks

@interface FakeDrag : NSObject <NSDraggingInfo>
@property(strong) NSPasteboard *pb;
@property(weak) NSWindow *win;
@end

@implementation FakeDrag
@synthesize draggingFormation;
@synthesize animatesToDestination;
@synthesize numberOfValidItemsForDrop;
- (NSWindow *)draggingDestinationWindow {
    return self.win;
}
- (NSDragOperation)draggingSourceOperationMask {
    return NSDragOperationCopy | NSDragOperationGeneric;
}
- (NSPoint)draggingLocation {
    return NSMakePoint(50, 50);
}
- (NSPoint)draggedImageLocation {
    return NSMakePoint(50, 50);
}
- (NSImage *)draggedImage {
    return nil;
}
- (NSPasteboard *)draggingPasteboard {
    return self.pb;
}
- (id)draggingSource {
    return nil;
}
- (NSInteger)draggingSequenceNumber {
    return 1;
}
- (void)slideDraggedImageTo:(NSPoint)screenPoint {
    (void)screenPoint;
}
- (NSSpringLoadingHighlight)springLoadingHighlight {
    return NSSpringLoadingHighlightNone;
}
- (void)resetSpringLoading {
}
- (void)enumerateDraggingItemsWithOptions:(NSDraggingItemEnumerationOptions)enumOpts
                                  forView:(NSView *)view
                                  classes:(NSArray<Class> *)classArray
                            searchOptions:(NSDictionary<NSPasteboardReadingOptionKey, id> *)searchOptions
                               usingBlock:(void (^)(NSDraggingItem *, NSInteger, BOOL *))block {
    (void)enumOpts, (void)view, (void)classArray, (void)searchOptions, (void)block;
}
@end

static FakeDrag *fake(NSWindow *w, void (^fill)(NSPasteboard *)) {
    FakeDrag *d = [FakeDrag new];
    d.pb = [NSPasteboard pasteboardWithUniqueName];
    [d.pb clearContents];
    fill(d.pb);
    d.win = w;
    return d;
}

static void reset(void) {
    [imports removeAllObjects];
    [notes removeAllObjects];
    [sdl_drops removeAllObjects];
}

static void test_fake_drops(NSWindow<NSDraggingDestination> *w) {
    NSString *dir = [NSTemporaryDirectory() stringByAppendingPathComponent:@"drop_test"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *kick = [dir stringByAppendingPathComponent:@"kick.wav"];
    [@"kick" writeToFile:kick atomically:NO encoding:NSUTF8StringEncoding error:NULL];

    // a Finder file: SDL's, as before
    reset();
    FakeDrag *d = fake(w, ^(NSPasteboard *pb) {
      [pb writeObjects:@[ [NSURL fileURLWithPath:kick] ]];
    });
    NSDragOperation op = [w draggingEntered:d];
    CHECK(op != NSDragOperationNone, "a file is taken (%lu)", (unsigned long)op);
    CHECK([w performDragOperation:d], "file drop performed");
    pump(1, ^BOOL {
      return sdl_drops.count > 0;
    });
    CHECK(sdl_drops.count == 1 && [sdl_drops[0] isEqualToString:kick], "SDL gets the file: %s",
          sdl_drops.description.UTF8String);
    CHECK(imports.count == 0 && notes.count == 0, "nothing else for a file");

    // wav data, no file: written for the drop and taken
    reset();
    NSData *wav = [@"RIFF....WAVEfmt " dataUsingEncoding:NSASCIIStringEncoding];
    d = fake(w, ^(NSPasteboard *pb) {
      [pb setData:wav forType:UTTypeWAV.identifier];
    });
    op = [w draggingEntered:d];
    CHECK(op == NSDragOperationCopy, "wav data is taken as a copy (%lu)", (unsigned long)op);
    CHECK([w performDragOperation:d], "data drop performed");
    pump(1, ^BOOL {
      return imports.count > 0;
    });
    CHECK(imports.count == 1, "wav data imported once (%lu)", (unsigned long)imports.count);
    if (imports.count == 1) {
        NSString *p = imports[0][@"path"];
        CHECK([p hasSuffix:@"/dropped audio.wav"], "named with its extension: %s", p.UTF8String);
        CHECK([imports[0][@"mode"] intValue] == MAC_IMPORT_TAKE, "taken (copied, then removed)");
        CHECK([imports[0][@"data"] isEqualToData:wav], "the dropped bytes");
        CHECK([p containsString:@"/norns-drops/"], "in a folder of its own: %s", p.UTF8String);
    }
    CHECK(sdl_drops.count == 0, "SDL is not asked");

    // aiff data
    reset();
    d = fake(w, ^(NSPasteboard *pb) {
      [pb setData:wav forType:UTTypeAIFF.identifier];
    });
    CHECK([w draggingEntered:d] == NSDragOperationCopy && [w performDragOperation:d], "aiff data");
    pump(1, ^BOOL {
      return imports.count > 0;
    });
    CHECK(imports.count == 1 && [imports[0][@"path"] hasSuffix:@".aiff"], "aiff named .aiff: %s",
          imports.description.UTF8String);

    // text only: SDL's, and a word that it is nothing for norns
    reset();
    d = fake(w, ^(NSPasteboard *pb) {
      [pb setString:@"just text" forType:NSPasteboardTypeString];
    });
    [w draggingEntered:d];
    [w performDragOperation:d];
    pump(0.5, nil);
    CHECK(imports.count == 0, "text is not imported");
    CHECK(notes.count == 1 && [notes[0] containsString:@"no audio file"], "says so: %s", notes.description.UTF8String);

    // a file and data: the file (the Finder's way) wins
    reset();
    d = fake(w, ^(NSPasteboard *pb) {
      NSPasteboardItem *it = [NSPasteboardItem new];
      [it setString:[NSURL fileURLWithPath:kick].absoluteString forType:NSPasteboardTypeFileURL];
      [it setData:wav forType:UTTypeWAV.identifier];
      [pb writeObjects:@[ it ]];
    });
    [w draggingEntered:d];
    [w performDragOperation:d];
    pump(1, ^BOOL {
      return sdl_drops.count > 0;
    });
    CHECK(sdl_drops.count == 1 && imports.count == 0, "file over data (sdl %lu, ours %lu)",
          (unsigned long)sdl_drops.count, (unsigned long)imports.count);
}

//--- a real drag of a promised file from another process

@interface Source : NSView <NSFilePromiseProviderDelegate, NSDraggingSource>
@end

@implementation Source
- (void)drawRect:(NSRect)r {
    [[NSColor systemOrangeColor] set];
    NSRectFill(r);
}
- (void)mouseDown:(NSEvent *)e {
    fprintf(stderr, "drag source: mouse down, dragging\n");
    NSFilePromiseProvider *p = [[NSFilePromiseProvider alloc] initWithFileType:UTTypeWAV.identifier delegate:self];
    NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:p];
    [item setDraggingFrame:NSMakeRect(0, 0, 40, 40) contents:nil];
    [self beginDraggingSessionWithItems:@[ item ] event:e source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)s sourceOperationMaskForDraggingContext:(NSDraggingContext)c {
    (void)s, (void)c;
    return NSDragOperationCopy;
}
- (NSString *)filePromiseProvider:(NSFilePromiseProvider *)p fileNameForType:(NSString *)type {
    (void)p, (void)type;
    return @"promised loop.wav";
}
- (void)filePromiseProvider:(NSFilePromiseProvider *)p
          writePromiseToURL:(NSURL *)url
          completionHandler:(void (^)(NSError *))done {
    (void)p;
    NSError *err = nil;
    [[@"promised bytes" dataUsingEncoding:NSUTF8StringEncoding] writeToURL:url options:0 error:&err];
    done(err);
}
@end

// the drag source process: a window at x y (points, top left), until killed
static int run_source(double x, double y) {
    [NSApplication sharedApplication];
    [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
    NSRect screen = [NSScreen screens][0].frame;
    NSWindow *w = [[NSWindow alloc] initWithContentRect:NSMakeRect(x, screen.size.height - y - 160, 160, 160)
                                              styleMask:NSWindowStyleMaskTitled
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    w.title = @"drag source";
    w.contentView = [[Source alloc] initWithFrame:NSMakeRect(0, 0, 160, 160)];
    [w makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    NSRect f = w.frame;
    fprintf(stderr, "drag source: window at %.0f %.0f (top left, points)\n", f.origin.x,
            screen.size.height - f.origin.y - f.size.height);
    [NSApp run];
    return 0;
}

static void mouse(CGEventType t, CGPoint p) {
    CGEventRef e = CGEventCreateMouseEvent(NULL, t, p, kCGMouseButtonLeft);
    CGEventPost(kCGHIDEventTap, e);
    CFRelease(e);
}

static void test_live_promise(SDL_Window *sw, const char *self_path) {
    int wx, wy, ww, wh;
    SDL_GetWindowPosition(sw, &wx, &wy);
    SDL_GetWindowSize(sw, &ww, &wh);
    double sx = wx - 260, sy = wy;
    // above everything else, or the drag ends in whatever window is in front of it
    [NSApp activateIgnoringOtherApps:YES];
    SDL_RaiseWindow(sw);
    pump(0.5, nil);
    NSTask *src = [NSTask launchedTaskWithLaunchPath:@(self_path)
                                           arguments:@[ @"source", @(sx).stringValue, @(sy).stringValue ]];
    pump(2.5, nil);
    reset();
    // content center of the source window (title bar ~28 points)
    CGPoint a = {sx + 80, sy + 28 + 80}, b = {wx + ww / 2.0, wy + wh / 2.0};
    mouse(kCGEventMouseMoved, a);
    pump(0.1, nil);
    mouse(kCGEventLeftMouseDown, a);
    pump(0.1, nil);
    for (int i = 1; i <= 30; i++) {
        CGPoint p = {a.x + (b.x - a.x) * i / 30, a.y + (b.y - a.y) * i / 30};
        mouse(kCGEventLeftMouseDragged, p);
        pump(0.03, nil);
    }
    pump(0.3, nil);
    if (getenv("DROP_TEST_SHOT") != NULL) {
        system([NSString stringWithFormat:@"screencapture -x '%s'", getenv("DROP_TEST_SHOT")].UTF8String);
    }
    mouse(kCGEventLeftMouseUp, b);
    pump(5, ^BOOL {
      return imports.count > 0;
    });
    [src terminate];
    CHECK(imports.count == 1, "promised file arrives (%lu, notes %s)", (unsigned long)imports.count,
          notes.description.UTF8String);
    if (imports.count == 1) {
        NSString *p = imports[0][@"path"];
        CHECK([p hasSuffix:@"/promised loop.wav"], "named by the app: %s", p.UTF8String);
        CHECK([imports[0][@"mode"] intValue] == MAC_IMPORT_TAKE, "taken");
        CHECK([[[NSString alloc] initWithData:imports[0][@"data"] encoding:NSUTF8StringEncoding]
                  isEqualToString:@"promised bytes"],
              "the app's bytes");
    }
    CHECK(sdl_drops.count == 0, "SDL gets nothing");
    CHECK(notes.count == 1 && [notes[0] containsString:@"getting the file"], "says it is coming: %s",
          notes.description.UTF8String);
    printf("live promise drag: %s\n", imports.count == 1 ? "arrived" : "did not arrive");
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc >= 4 && strcmp(argv[1], "source") == 0) {
            return run_source(atof(argv[2]), atof(argv[3]));
        }
        imports = [NSMutableArray array];
        notes = [NSMutableArray array];
        sdl_drops = [NSMutableArray array];
        if (SDL_Init(SDL_INIT_VIDEO) != 0) {
            printf("no SDL video: %s\n", SDL_GetError());
            return 1;
        }
        SDL_EventState(SDL_DROPFILE, SDL_ENABLE);
        SDL_Window *sw = SDL_CreateWindow("drop here", 700, 300, 300, 200, SDL_WINDOW_SHOWN);
        mac_menu_install(on_item, on_import, on_note);
        mac_drop_adopt_windows();
        pump(0.5, nil);
        NSWindow *w = nil;
        for (NSWindow *x in [NSApp windows]) {
            if ([x.title isEqualToString:@"drop here"]) {
                w = x;
            }
        }
        CHECK(w != nil, "the SDL window");
        if (w != nil) {
            test_fake_drops((NSWindow<NSDraggingDestination> *)w);
            if (argc > 1 && strcmp(argv[1], "--live") == 0) {
                test_live_promise(sw, argv[0]);
            }
        }
        SDL_DestroyWindow(sw);
        SDL_Quit();
        printf("%s: %d failures\n", failures ? "FAILED" : "drops ok", failures);
        return failures != 0;
    }
}
