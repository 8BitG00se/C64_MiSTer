// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design internal header
// See Vsid_fx.h for the primary calling header

#ifndef VERILATED_VSID_FX___024ROOT_H_
#define VERILATED_VSID_FX___024ROOT_H_  // guard

#include "verilated.h"


class Vsid_fx__Syms;

class alignas(VL_CACHE_LINE_BYTES) Vsid_fx___024root final : public VerilatedModule {
  public:

    // DESIGN SPECIFIC STATE
    VL_IN8(clk,0,0);
    VL_IN8(reset,0,0);
    VL_IN8(ce_1m,0,0);
    VL_IN8(mode,1,0);
    VL_IN8(cpu_wr,0,0);
    VL_IN8(sid1_wr,0,0);
    VL_IN8(addr,4,0);
    VL_IN8(data,7,0);
    VL_IN8(busy1,0,0);
    VL_IN8(busy2,0,0);
    VL_OUT8(inj_we,0,0);
    VL_OUT8(inj_tgt,1,0);
    VL_OUT8(inj_addr,4,0);
    VL_OUT8(inj_data,7,0);
    CData/*1:0*/ sid_fx__DOT__vo;
    CData/*4:0*/ sid_fx__DOT__vb;
    CData/*0:0*/ sid_fx__DOT__is_freq;
    CData/*0:0*/ sid_fx__DOT__pa;
    CData/*0:0*/ sid_fx__DOT__pb;
    CData/*4:0*/ sid_fx__DOT__pa_a;
    CData/*4:0*/ sid_fx__DOT__pb_a;
    CData/*7:0*/ sid_fx__DOT__pa_d;
    CData/*1:0*/ sid_fx__DOT__pv;
    CData/*0:0*/ sid_fx__DOT__fq_wait;
    CData/*0:0*/ sid_fx__DOT__tl_v;
    CData/*0:0*/ sid_fx__DOT__tr_v;
    CData/*1:0*/ sid_fx__DOT__fetch;
    CData/*0:0*/ sid_fx__DOT__fetch2;
    CData/*0:0*/ sid_fx__DOT__due_l;
    CData/*0:0*/ sid_fx__DOT__due_r;
    CData/*7:0*/ sid_fx__DOT____Vlvbound_hea9e1deb__0;
    CData/*7:0*/ sid_fx__DOT____Vlvbound_heaa5aae3__0;
    CData/*0:0*/ __VstlFirstIteration;
    CData/*0:0*/ __VicoFirstIteration;
    CData/*0:0*/ __Vtrigprevexpr___TOP__clk__0;
    CData/*0:0*/ __VactContinue;
    SData/*15:0*/ sid_fx__DOT__sharp;
    SData/*10:0*/ sid_fx__DOT__wp;
    SData/*10:0*/ sid_fx__DOT__rl;
    SData/*10:0*/ sid_fx__DOT__rr;
    SData/*10:0*/ sid_fx__DOT__ra;
    IData/*19:0*/ sid_fx__DOT__now;
    IData/*31:0*/ __VactIterCount;
    QData/*32:0*/ sid_fx__DOT__rq;
    QData/*32:0*/ sid_fx__DOT__tl;
    QData/*32:0*/ sid_fx__DOT__tr;
    VlUnpacked<SData/*15:0*/, 3> sid_fx__DOT__freq;
    VlUnpacked<QData/*32:0*/, 2048> sid_fx__DOT__ring__DOT__m;
    VlTriggerVec<1> __VstlTriggered;
    VlTriggerVec<1> __VicoTriggered;
    VlTriggerVec<1> __VactTriggered;
    VlTriggerVec<1> __VnbaTriggered;

    // INTERNAL VARIABLES
    Vsid_fx__Syms* const vlSymsp;

    // CONSTRUCTORS
    Vsid_fx___024root(Vsid_fx__Syms* symsp, const char* v__name);
    ~Vsid_fx___024root();
    VL_UNCOPYABLE(Vsid_fx___024root);

    // INTERNAL METHODS
    void __Vconfigure(bool first);
};


#endif  // guard
