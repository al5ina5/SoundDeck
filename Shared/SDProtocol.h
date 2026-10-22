#pragma once
#import <Foundation/Foundation.h>
#import <notify.h>
#include <stdint.h>
#include <math.h>
#include <sys/stat.h>
#ifndef SD_DIR
#define SD_DIR @"/var/mobile/Library/SoundDeck"
#endif
#define SD_PREFS SD_DIR @"/preferences.plist"
#define SD_STATUS SD_DIR @"/status.plist"
#define SD_CHANGED "com.alsinas.sounddeck.preferences"
#define SD_GLOBAL "com.alsinas.sounddeck.global"
#define SD_VERSION @"0.1.0"
static inline uint64_t SDGlobalState(NSDictionary *p);
// notifyd is the cross-sandbox transport; no file access on audio threads or in clients.
// config: gain in 0..1000, mute bit 10, enabled bit 11, mix bit 12.
static inline NSString *SDGainName(NSString *bid) { return [@"com.alsinas.sounddeck.gain." stringByAppendingString:bid]; }
static inline NSString *SDClientName(pid_t pid) { return [NSString stringWithFormat:@"com.alsinas.sounddeck.client.%d",pid]; }
static inline uint64_t SDConfig(NSDictionary *p, NSDictionary *a) {
    double gain = a[@"gain"] ? [a[@"gain"] doubleValue] : 1.;
    if (!isfinite(gain)) gain = 1.;
    return (uint64_t)llround(fmax(0.,fmin(1.,gain))*1000.) |
        ([a[@"muted"] boolValue] ? 1ULL<<10 : 0) |
        (![p[@"disabled"] boolValue] ? 1ULL<<11 : 0) |
        ([p[@"mixing"] boolValue] ? 1ULL<<12 : 0);
}
static inline uint64_t SDGlobalState(NSDictionary *p) {
    return SDConfig(p,nil)|(((uint64_t)NSDate.date.timeIntervalSince1970&65535)<<32);
}
static inline BOOL SDGlobalFresh(uint64_t state) {
    unsigned now=(uint64_t)NSDate.date.timeIntervalSince1970&65535;
    return state && ((now-((state>>32)&65535))&65535)<5;
}
NSDictionary *SDSanitizePrefs(NSDictionary *input);
NSDictionary *SDReadPrefs(void);
// Client state: active(1), path(3), effective gain(10), input RMS(16), output RMS(16), seconds modulo 65536(16).
static inline uint64_t SDClientState(BOOL active, unsigned path, unsigned gain, unsigned inRMS, unsigned outRMS) {
    return (active?1ULL:0) | ((uint64_t)(path&7)<<1) | ((uint64_t)(gain&1023)<<4) |
      ((uint64_t)(inRMS&65535)<<14) | ((uint64_t)(outRMS&65535)<<30) |
      ((uint64_t)((uint64_t)NSDate.date.timeIntervalSince1970&65535)<<46);
}
static inline BOOL SDFresh(uint64_t s) {
    unsigned now = (uint64_t)NSDate.date.timeIntervalSince1970 & 65535;
    return s && ((now - ((s>>46)&65535))&65535) < 4;
}
static inline NSString *SDPathName(unsigned n) {
    return @[@"Waiting for audio",@"RemoteIO PCM",@"AudioQueue",@"AVPlayer",@"AVAudioPlayer",@"Sample buffer",@"Unsupported",@"Unknown"][n&7];
}
BOOL SDWritePrefs(NSDictionary *prefs, NSError **error);
BOOL SDUpdatePrefs(NSDictionary *changes, NSError **error);
