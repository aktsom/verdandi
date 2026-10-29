#include <SDL2/SDL.h>
#include <stdio.h>
int main(void) {
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Window *w = SDL_CreateWindow("t", 100, 100, 640, 320, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_ALLOW_HIGHDPI);
    SDL_Delay(300);
    int a, b; SDL_GetWindowSize(w, &a, &b); printf("windowed %dx%d, driver %s\n", a, b, SDL_GetCurrentVideoDriver());
    int rc = SDL_SetWindowFullscreen(w, SDL_WINDOW_FULLSCREEN_DESKTOP);
    for (int i = 0; i < 20; i++) { SDL_Event e; while (SDL_PollEvent(&e)) {} SDL_Delay(50); }
    SDL_GetWindowSize(w, &a, &b); printf("fullscreen rc=%d now %dx%d flags %x\n", rc, a, b, SDL_GetWindowFlags(w) & SDL_WINDOW_FULLSCREEN_DESKTOP);
    SDL_SetWindowFullscreen(w, 0);
    for (int i = 0; i < 20; i++) { SDL_Event e; while (SDL_PollEvent(&e)) {} SDL_Delay(50); }
    SDL_GetWindowSize(w, &a, &b); printf("back: %dx%d\n", a, b);
    SDL_Window *w2 = SDL_CreateWindow("b", 100, 100, 640, 320, SDL_WINDOW_SHOWN | SDL_WINDOW_RESIZABLE | SDL_WINDOW_BORDERLESS);
    printf("borderless window %s; hit test rc=%d\n", w2 ? "ok" : "failed", w2 ? SDL_SetWindowHitTest(w2, NULL, NULL) : -1);
    return 0;
}
