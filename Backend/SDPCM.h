#pragma once
#include <AudioToolbox/AudioToolbox.h>
#include <cmath>
#include <cstring>
// Packed LPCM only. Explicit endian/float handling also covers stereo and planar buffers.
struct SDPCMFormat { unsigned bytes=0; bool floating=false,sign=false,big=false; double divisor=1; };
static inline SDPCMFormat SDDescribePCM(const AudioStreamBasicDescription &f) {
    SDPCMFormat d;
    if(f.mFormatID!=kAudioFormatLinearPCM || !(f.mFormatFlags&kAudioFormatFlagIsPacked) || f.mBitsPerChannel%8) return d;
    d.bytes=f.mBitsPerChannel/8; d.floating=f.mFormatFlags&kAudioFormatFlagIsFloat;
    d.sign=f.mFormatFlags&kAudioFormatFlagIsSignedInteger; d.big=f.mFormatFlags&kAudioFormatFlagIsBigEndian;
    if(d.floating?(d.bytes!=4 && d.bytes!=8):(d.bytes<1 || d.bytes>4)) { d.bytes=0; return d; }
    unsigned fraction=(f.mFormatFlags&kLinearPCMFormatFlagsSampleFractionMask)>>kLinearPCMFormatFlagsSampleFractionShift;
    d.divisor=std::ldexp(1.,fraction?fraction:(int)f.mBitsPerChannel-1);
    return d;
}
static inline double SDReadSample(const unsigned char *p,SDPCMFormat d) {
    uint64_t bits=0;
    for(unsigned i=0;i<d.bytes;i++) bits|=(uint64_t)p[d.big?d.bytes-1-i:i]<<(i*8);
    if(d.floating) { if(d.bytes==4) { uint32_t b=(uint32_t)bits; float v; memcpy(&v,&b,4); return v; } double v; memcpy(&v,&bits,8); return v; }
    int64_t value;
    if(d.sign) { unsigned shift=64-d.bytes*8; value=(int64_t)(bits<<shift)>>shift; }
    else value=(int64_t)bits-(1LL<<(d.bytes*8-1));
    return value/d.divisor;
}
static inline void SDWriteSample(unsigned char *p,SDPCMFormat d,double value) {
    uint64_t bits;
    if(d.floating) { if(d.bytes==4) { float v=(float)value; uint32_t b; memcpy(&b,&v,4); bits=b; } else memcpy(&bits,&value,8); }
    else {
        int64_t lo=-(1LL<<(d.bytes*8-1)),hi=(1LL<<(d.bytes*8-1))-1;
        int64_t v=(int64_t)llround(fmax((double)lo,fmin((double)hi,value*d.divisor)));
        bits=d.sign?(uint64_t)v:(uint64_t)(v-lo);
    }
    for(unsigned i=0;i<d.bytes;i++) p[d.big?d.bytes-1-i:i]=(unsigned char)(bits>>(i*8));
}
