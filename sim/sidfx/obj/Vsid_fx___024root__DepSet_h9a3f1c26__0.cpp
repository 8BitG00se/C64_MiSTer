// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vsid_fx.h for the primary calling header

#include "Vsid_fx__pch.h"
#include "Vsid_fx___024root.h"

void Vsid_fx___024root___ico_sequent__TOP__0(Vsid_fx___024root* vlSelf);

void Vsid_fx___024root___eval_ico(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_ico\n"); );
    // Body
    if ((1ULL & vlSelf->__VicoTriggered.word(0U))) {
        Vsid_fx___024root___ico_sequent__TOP__0(vlSelf);
    }
}

VL_INLINE_OPT void Vsid_fx___024root___ico_sequent__TOP__0(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___ico_sequent__TOP__0\n"); );
    // Body
    vlSelf->sid_fx__DOT__vo = ((7U > (IData)(vlSelf->addr))
                                ? 0U : ((0xeU > (IData)(vlSelf->addr))
                                         ? 1U : 2U));
    vlSelf->sid_fx__DOT__vb = ((0U == (IData)(vlSelf->sid_fx__DOT__vo))
                                ? 0U : ((1U == (IData)(vlSelf->sid_fx__DOT__vo))
                                         ? 7U : 0xeU));
    vlSelf->sid_fx__DOT__is_freq = ((0x15U > (IData)(vlSelf->addr)) 
                                    & (2U > (0x1fU 
                                             & ((IData)(vlSelf->addr) 
                                                - (IData)(vlSelf->sid_fx__DOT__vb)))));
}

void Vsid_fx___024root___eval_triggers__ico(Vsid_fx___024root* vlSelf);

bool Vsid_fx___024root___eval_phase__ico(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_phase__ico\n"); );
    // Init
    CData/*0:0*/ __VicoExecute;
    // Body
    Vsid_fx___024root___eval_triggers__ico(vlSelf);
    __VicoExecute = vlSelf->__VicoTriggered.any();
    if (__VicoExecute) {
        Vsid_fx___024root___eval_ico(vlSelf);
    }
    return (__VicoExecute);
}

void Vsid_fx___024root___eval_act(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_act\n"); );
}

void Vsid_fx___024root___nba_sequent__TOP__0(Vsid_fx___024root* vlSelf);

void Vsid_fx___024root___eval_nba(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_nba\n"); );
    // Body
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        Vsid_fx___024root___nba_sequent__TOP__0(vlSelf);
    }
}

VL_INLINE_OPT void Vsid_fx___024root___nba_sequent__TOP__0(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___nba_sequent__TOP__0\n"); );
    // Init
    SData/*15:0*/ sid_fx__DOT__fq;
    sid_fx__DOT__fq = 0;
    CData/*7:0*/ __Vfunc_sid_fx__DOT__half_vol__0__Vfuncout;
    __Vfunc_sid_fx__DOT__half_vol__0__Vfuncout = 0;
    CData/*4:0*/ __Vfunc_sid_fx__DOT__half_vol__0__a;
    __Vfunc_sid_fx__DOT__half_vol__0__a = 0;
    CData/*7:0*/ __Vfunc_sid_fx__DOT__half_vol__0__d;
    __Vfunc_sid_fx__DOT__half_vol__0__d = 0;
    CData/*7:0*/ __Vfunc_sid_fx__DOT__half_vol__1__Vfuncout;
    __Vfunc_sid_fx__DOT__half_vol__1__Vfuncout = 0;
    CData/*4:0*/ __Vfunc_sid_fx__DOT__half_vol__1__a;
    __Vfunc_sid_fx__DOT__half_vol__1__a = 0;
    CData/*7:0*/ __Vfunc_sid_fx__DOT__half_vol__1__d;
    __Vfunc_sid_fx__DOT__half_vol__1__d = 0;
    IData/*19:0*/ __Vdly__sid_fx__DOT__now;
    __Vdly__sid_fx__DOT__now = 0;
    CData/*7:0*/ __VdlyVal__sid_fx__DOT__freq__v3;
    __VdlyVal__sid_fx__DOT__freq__v3 = 0;
    CData/*1:0*/ __VdlyDim0__sid_fx__DOT__freq__v3;
    __VdlyDim0__sid_fx__DOT__freq__v3 = 0;
    CData/*7:0*/ __VdlyVal__sid_fx__DOT__freq__v4;
    __VdlyVal__sid_fx__DOT__freq__v4 = 0;
    CData/*1:0*/ __VdlyDim0__sid_fx__DOT__freq__v4;
    __VdlyDim0__sid_fx__DOT__freq__v4 = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__pa;
    __Vdly__sid_fx__DOT__pa = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__pb;
    __Vdly__sid_fx__DOT__pb = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__fq_wait;
    __Vdly__sid_fx__DOT__fq_wait = 0;
    SData/*10:0*/ __Vdly__sid_fx__DOT__wp;
    __Vdly__sid_fx__DOT__wp = 0;
    SData/*10:0*/ __Vdly__sid_fx__DOT__rl;
    __Vdly__sid_fx__DOT__rl = 0;
    SData/*10:0*/ __Vdly__sid_fx__DOT__rr;
    __Vdly__sid_fx__DOT__rr = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__tl_v;
    __Vdly__sid_fx__DOT__tl_v = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__tr_v;
    __Vdly__sid_fx__DOT__tr_v = 0;
    CData/*1:0*/ __Vdly__sid_fx__DOT__fetch;
    __Vdly__sid_fx__DOT__fetch = 0;
    CData/*0:0*/ __Vdly__sid_fx__DOT__fetch2;
    __Vdly__sid_fx__DOT__fetch2 = 0;
    CData/*4:0*/ __Vdly__sid_fx__DOT__pa_a;
    __Vdly__sid_fx__DOT__pa_a = 0;
    CData/*7:0*/ __Vdly__sid_fx__DOT__pa_d;
    __Vdly__sid_fx__DOT__pa_d = 0;
    QData/*32:0*/ __Vdly__sid_fx__DOT__tl;
    __Vdly__sid_fx__DOT__tl = 0;
    QData/*32:0*/ __Vdly__sid_fx__DOT__tr;
    __Vdly__sid_fx__DOT__tr = 0;
    SData/*10:0*/ __Vdly__sid_fx__DOT__ra;
    __Vdly__sid_fx__DOT__ra = 0;
    QData/*32:0*/ __VdlyVal__sid_fx__DOT__ring__DOT__m__v0;
    __VdlyVal__sid_fx__DOT__ring__DOT__m__v0 = 0;
    SData/*10:0*/ __VdlyDim0__sid_fx__DOT__ring__DOT__m__v0;
    __VdlyDim0__sid_fx__DOT__ring__DOT__m__v0 = 0;
    CData/*0:0*/ __VdlySet__sid_fx__DOT__freq__v0;
    __VdlySet__sid_fx__DOT__freq__v0 = 0;
    CData/*0:0*/ __VdlySet__sid_fx__DOT__freq__v3;
    __VdlySet__sid_fx__DOT__freq__v3 = 0;
    CData/*0:0*/ __VdlySet__sid_fx__DOT__freq__v4;
    __VdlySet__sid_fx__DOT__freq__v4 = 0;
    CData/*0:0*/ __VdlySet__sid_fx__DOT__ring__DOT__m__v0;
    __VdlySet__sid_fx__DOT__ring__DOT__m__v0 = 0;
    // Body
    __Vdly__sid_fx__DOT__now = vlSelf->sid_fx__DOT__now;
    __VdlySet__sid_fx__DOT__ring__DOT__m__v0 = 0U;
    __VdlySet__sid_fx__DOT__freq__v0 = 0U;
    __VdlySet__sid_fx__DOT__freq__v3 = 0U;
    __VdlySet__sid_fx__DOT__freq__v4 = 0U;
    __Vdly__sid_fx__DOT__ra = vlSelf->sid_fx__DOT__ra;
    __Vdly__sid_fx__DOT__pa_d = vlSelf->sid_fx__DOT__pa_d;
    __Vdly__sid_fx__DOT__pa_a = vlSelf->sid_fx__DOT__pa_a;
    __Vdly__sid_fx__DOT__fetch2 = vlSelf->sid_fx__DOT__fetch2;
    __Vdly__sid_fx__DOT__fetch = vlSelf->sid_fx__DOT__fetch;
    __Vdly__sid_fx__DOT__rr = vlSelf->sid_fx__DOT__rr;
    __Vdly__sid_fx__DOT__rl = vlSelf->sid_fx__DOT__rl;
    __Vdly__sid_fx__DOT__wp = vlSelf->sid_fx__DOT__wp;
    __Vdly__sid_fx__DOT__fq_wait = vlSelf->sid_fx__DOT__fq_wait;
    __Vdly__sid_fx__DOT__pb = vlSelf->sid_fx__DOT__pb;
    __Vdly__sid_fx__DOT__pa = vlSelf->sid_fx__DOT__pa;
    __Vdly__sid_fx__DOT__tr = vlSelf->sid_fx__DOT__tr;
    __Vdly__sid_fx__DOT__tl = vlSelf->sid_fx__DOT__tl;
    __Vdly__sid_fx__DOT__tr_v = vlSelf->sid_fx__DOT__tr_v;
    __Vdly__sid_fx__DOT__tl_v = vlSelf->sid_fx__DOT__tl_v;
    if (((~ (IData)(vlSelf->reset)) & ((IData)(vlSelf->sid1_wr) 
                                       & (((IData)(vlSelf->mode) 
                                           >> 1U) & 
                                          (0x19U > (IData)(vlSelf->addr)))))) {
        __VdlyVal__sid_fx__DOT__ring__DOT__m__v0 = 
            (((QData)((IData)(vlSelf->sid_fx__DOT__now)) 
              << 0xdU) | (QData)((IData)((((IData)(vlSelf->addr) 
                                           << 8U) | (IData)(vlSelf->data)))));
        __VdlyDim0__sid_fx__DOT__ring__DOT__m__v0 = vlSelf->sid_fx__DOT__wp;
        __VdlySet__sid_fx__DOT__ring__DOT__m__v0 = 1U;
    }
    vlSelf->inj_we = 0U;
    if (vlSelf->reset) {
        __Vdly__sid_fx__DOT__now = 0U;
        __VdlySet__sid_fx__DOT__freq__v0 = 1U;
        __Vdly__sid_fx__DOT__pa = 0U;
        __Vdly__sid_fx__DOT__pb = 0U;
        __Vdly__sid_fx__DOT__fq_wait = 0U;
        __Vdly__sid_fx__DOT__wp = 0U;
        __Vdly__sid_fx__DOT__rl = 0U;
        __Vdly__sid_fx__DOT__rr = 0U;
        __Vdly__sid_fx__DOT__tl_v = 0U;
        __Vdly__sid_fx__DOT__tr_v = 0U;
        __Vdly__sid_fx__DOT__fetch = 0U;
        __Vdly__sid_fx__DOT__fetch2 = 0U;
    } else {
        if (vlSelf->ce_1m) {
            __Vdly__sid_fx__DOT__now = (0xfffffU & 
                                        ((IData)(1U) 
                                         + vlSelf->sid_fx__DOT__now));
        }
        if (vlSelf->sid1_wr) {
            if (vlSelf->sid_fx__DOT__is_freq) {
                if (((IData)(vlSelf->addr) == (IData)(vlSelf->sid_fx__DOT__vb))) {
                    vlSelf->sid_fx__DOT____Vlvbound_hea9e1deb__0 
                        = vlSelf->data;
                    if ((2U >= (IData)(vlSelf->sid_fx__DOT__vo))) {
                        __VdlyVal__sid_fx__DOT__freq__v3 
                            = vlSelf->sid_fx__DOT____Vlvbound_hea9e1deb__0;
                        __VdlyDim0__sid_fx__DOT__freq__v3 
                            = vlSelf->sid_fx__DOT__vo;
                        __VdlySet__sid_fx__DOT__freq__v3 = 1U;
                    }
                } else {
                    vlSelf->sid_fx__DOT____Vlvbound_heaa5aae3__0 
                        = vlSelf->data;
                    if ((2U >= (IData)(vlSelf->sid_fx__DOT__vo))) {
                        __VdlyVal__sid_fx__DOT__freq__v4 
                            = vlSelf->sid_fx__DOT____Vlvbound_heaa5aae3__0;
                        __VdlyDim0__sid_fx__DOT__freq__v4 
                            = vlSelf->sid_fx__DOT__vo;
                        __VdlySet__sid_fx__DOT__freq__v4 = 1U;
                    }
                }
            }
            if ((1U & (IData)(vlSelf->mode))) {
                if (vlSelf->sid_fx__DOT__is_freq) {
                    __Vdly__sid_fx__DOT__fq_wait = 1U;
                    __Vdly__sid_fx__DOT__pa_a = vlSelf->sid_fx__DOT__vb;
                } else {
                    __Vdly__sid_fx__DOT__pa = 1U;
                    __Vdly__sid_fx__DOT__pa_a = vlSelf->addr;
                    __Vdly__sid_fx__DOT__pa_d = vlSelf->data;
                }
            }
            if ((((IData)(vlSelf->mode) >> 1U) & (0x19U 
                                                  > (IData)(vlSelf->addr)))) {
                __Vdly__sid_fx__DOT__wp = (0x7ffU & 
                                           ((IData)(1U) 
                                            + (IData)(vlSelf->sid_fx__DOT__wp)));
                if (((0x7ffU & ((IData)(1U) + (IData)(vlSelf->sid_fx__DOT__wp))) 
                     == (IData)(vlSelf->sid_fx__DOT__rr))) {
                    __Vdly__sid_fx__DOT__rr = (0x7ffU 
                                               & ((IData)(1U) 
                                                  + (IData)(vlSelf->sid_fx__DOT__rr)));
                    __Vdly__sid_fx__DOT__tr_v = 0U;
                    if (((IData)(vlSelf->sid_fx__DOT__rl) 
                         == (IData)(vlSelf->sid_fx__DOT__rr))) {
                        __Vdly__sid_fx__DOT__rl = (0x7ffU 
                                                   & ((IData)(1U) 
                                                      + (IData)(vlSelf->sid_fx__DOT__rl)));
                        __Vdly__sid_fx__DOT__tl_v = 0U;
                    }
                }
            }
        }
        if (vlSelf->sid_fx__DOT__fq_wait) {
            __Vdly__sid_fx__DOT__fq_wait = 0U;
            __Vdly__sid_fx__DOT__pa = 1U;
            __Vdly__sid_fx__DOT__pb = 1U;
            __Vdly__sid_fx__DOT__pa_d = (0xffU & (IData)(vlSelf->sid_fx__DOT__sharp));
        }
        if (((((IData)(vlSelf->sid1_wr) & ((IData)(vlSelf->mode) 
                                           >> 1U)) 
              & ((0x7ffU & ((IData)(1U) + (IData)(vlSelf->sid_fx__DOT__wp))) 
                 == (IData)(vlSelf->sid_fx__DOT__rr))) 
             & (0U != (IData)(vlSelf->sid_fx__DOT__fetch)))) {
            __Vdly__sid_fx__DOT__fetch = 0U;
            __Vdly__sid_fx__DOT__fetch2 = 0U;
        } else if (vlSelf->sid_fx__DOT__fetch2) {
            __Vdly__sid_fx__DOT__fetch2 = 0U;
            if ((1U == (IData)(vlSelf->sid_fx__DOT__fetch))) {
                __Vdly__sid_fx__DOT__tl = vlSelf->sid_fx__DOT__rq;
                __Vdly__sid_fx__DOT__tl_v = 1U;
            } else {
                __Vdly__sid_fx__DOT__tr = vlSelf->sid_fx__DOT__rq;
                __Vdly__sid_fx__DOT__tr_v = 1U;
            }
            __Vdly__sid_fx__DOT__fetch = 0U;
        } else if ((0U != (IData)(vlSelf->sid_fx__DOT__fetch))) {
            __Vdly__sid_fx__DOT__fetch2 = 1U;
        } else if ((((~ (IData)(vlSelf->sid_fx__DOT__tl_v)) 
                     & ((IData)(vlSelf->sid_fx__DOT__rl) 
                        != (IData)(vlSelf->sid_fx__DOT__wp))) 
                    & (~ ((IData)(vlSelf->sid1_wr) 
                          & ((IData)(vlSelf->mode) 
                             >> 1U))))) {
            __Vdly__sid_fx__DOT__ra = vlSelf->sid_fx__DOT__rl;
            __Vdly__sid_fx__DOT__fetch = 1U;
        } else if ((((~ (IData)(vlSelf->sid_fx__DOT__tr_v)) 
                     & ((IData)(vlSelf->sid_fx__DOT__rr) 
                        != (IData)(vlSelf->sid_fx__DOT__wp))) 
                    & (~ ((IData)(vlSelf->sid1_wr) 
                          & ((IData)(vlSelf->mode) 
                             >> 1U))))) {
            __Vdly__sid_fx__DOT__ra = vlSelf->sid_fx__DOT__rr;
            __Vdly__sid_fx__DOT__fetch = 2U;
        }
        if ((1U & (((~ (IData)(vlSelf->cpu_wr)) & (~ (IData)(vlSelf->sid1_wr))) 
                   & (~ (IData)(vlSelf->sid_fx__DOT__fq_wait))))) {
            if (((IData)(vlSelf->sid_fx__DOT__pa) & 
                 (~ (IData)(vlSelf->busy1)))) {
                vlSelf->inj_we = 1U;
                vlSelf->inj_tgt = 1U;
                vlSelf->inj_addr = vlSelf->sid_fx__DOT__pa_a;
                vlSelf->inj_data = vlSelf->sid_fx__DOT__pa_d;
                __Vdly__sid_fx__DOT__pa = 0U;
                if (vlSelf->sid_fx__DOT__pb) {
                    __Vdly__sid_fx__DOT__pa_d = (0xffU 
                                                 & ((IData)(vlSelf->sid_fx__DOT__sharp) 
                                                    >> 8U));
                    __Vdly__sid_fx__DOT__pa = 1U;
                    __Vdly__sid_fx__DOT__pa_a = vlSelf->sid_fx__DOT__pb_a;
                    __Vdly__sid_fx__DOT__pb = 0U;
                }
            } else if ((((IData)(vlSelf->sid_fx__DOT__due_l) 
                         & (~ (IData)(vlSelf->busy2))) 
                        & (1U != (IData)(vlSelf->sid_fx__DOT__fetch)))) {
                __Vdly__sid_fx__DOT__rl = (0x7ffU & 
                                           ((IData)(1U) 
                                            + (IData)(vlSelf->sid_fx__DOT__rl)));
                vlSelf->inj_we = 1U;
                vlSelf->inj_tgt = 2U;
                vlSelf->inj_addr = (0x1fU & (IData)(
                                                    (vlSelf->sid_fx__DOT__tl 
                                                     >> 8U)));
                __Vdly__sid_fx__DOT__tl_v = 0U;
                __Vfunc_sid_fx__DOT__half_vol__0__d 
                    = (0xffU & (IData)(vlSelf->sid_fx__DOT__tl));
                __Vfunc_sid_fx__DOT__half_vol__0__a 
                    = (0x1fU & (IData)((vlSelf->sid_fx__DOT__tl 
                                        >> 8U)));
                __Vfunc_sid_fx__DOT__half_vol__0__Vfuncout 
                    = ((0x18U == (IData)(__Vfunc_sid_fx__DOT__half_vol__0__a))
                        ? ((0xf0U & (IData)(__Vfunc_sid_fx__DOT__half_vol__0__d)) 
                           | (7U & ((IData)(__Vfunc_sid_fx__DOT__half_vol__0__d) 
                                    >> 1U))) : (IData)(__Vfunc_sid_fx__DOT__half_vol__0__d));
                vlSelf->inj_data = __Vfunc_sid_fx__DOT__half_vol__0__Vfuncout;
            } else if ((((IData)(vlSelf->sid_fx__DOT__due_r) 
                         & (~ (IData)(vlSelf->busy2))) 
                        & (2U != (IData)(vlSelf->sid_fx__DOT__fetch)))) {
                __Vdly__sid_fx__DOT__rr = (0x7ffU & 
                                           ((IData)(1U) 
                                            + (IData)(vlSelf->sid_fx__DOT__rr)));
                vlSelf->inj_we = 1U;
                vlSelf->inj_tgt = 3U;
                vlSelf->inj_addr = (0x1fU & (IData)(
                                                    (vlSelf->sid_fx__DOT__tr 
                                                     >> 8U)));
                __Vdly__sid_fx__DOT__tr_v = 0U;
                __Vfunc_sid_fx__DOT__half_vol__1__d 
                    = (0xffU & (IData)(vlSelf->sid_fx__DOT__tr));
                __Vfunc_sid_fx__DOT__half_vol__1__a 
                    = (0x1fU & (IData)((vlSelf->sid_fx__DOT__tr 
                                        >> 8U)));
                __Vfunc_sid_fx__DOT__half_vol__1__Vfuncout 
                    = ((0x18U == (IData)(__Vfunc_sid_fx__DOT__half_vol__1__a))
                        ? ((0xf0U & (IData)(__Vfunc_sid_fx__DOT__half_vol__1__d)) 
                           | (7U & ((IData)(__Vfunc_sid_fx__DOT__half_vol__1__d) 
                                    >> 1U))) : (IData)(__Vfunc_sid_fx__DOT__half_vol__1__d));
                vlSelf->inj_data = __Vfunc_sid_fx__DOT__half_vol__1__Vfuncout;
            }
        }
        if ((1U & (~ ((IData)(vlSelf->mode) >> 1U)))) {
            __Vdly__sid_fx__DOT__rl = vlSelf->sid_fx__DOT__wp;
            __Vdly__sid_fx__DOT__tl_v = 0U;
            __Vdly__sid_fx__DOT__tr_v = 0U;
            __Vdly__sid_fx__DOT__rr = vlSelf->sid_fx__DOT__wp;
        }
        if ((1U & (~ (IData)(vlSelf->mode)))) {
            __Vdly__sid_fx__DOT__pa = 0U;
            __Vdly__sid_fx__DOT__pb = 0U;
        }
    }
    if ((1U & (~ (IData)(vlSelf->reset)))) {
        if (vlSelf->sid1_wr) {
            if ((1U & (IData)(vlSelf->mode))) {
                if (vlSelf->sid_fx__DOT__is_freq) {
                    vlSelf->sid_fx__DOT__pv = vlSelf->sid_fx__DOT__vo;
                    vlSelf->sid_fx__DOT__pb_a = (0x1fU 
                                                 & ((IData)(1U) 
                                                    + (IData)(vlSelf->sid_fx__DOT__vb)));
                }
            }
        }
    }
    vlSelf->sid_fx__DOT__now = __Vdly__sid_fx__DOT__now;
    if (__VdlySet__sid_fx__DOT__freq__v0) {
        vlSelf->sid_fx__DOT__freq[0U] = 0U;
        vlSelf->sid_fx__DOT__freq[1U] = 0U;
        vlSelf->sid_fx__DOT__freq[2U] = 0U;
    }
    if (__VdlySet__sid_fx__DOT__freq__v3) {
        vlSelf->sid_fx__DOT__freq[__VdlyDim0__sid_fx__DOT__freq__v3] 
            = ((0xff00U & vlSelf->sid_fx__DOT__freq
                [__VdlyDim0__sid_fx__DOT__freq__v3]) 
               | (IData)(__VdlyVal__sid_fx__DOT__freq__v3));
    }
    if (__VdlySet__sid_fx__DOT__freq__v4) {
        vlSelf->sid_fx__DOT__freq[__VdlyDim0__sid_fx__DOT__freq__v4] 
            = ((0xffU & vlSelf->sid_fx__DOT__freq[__VdlyDim0__sid_fx__DOT__freq__v4]) 
               | ((IData)(__VdlyVal__sid_fx__DOT__freq__v4) 
                  << 8U));
    }
    vlSelf->sid_fx__DOT__pa = __Vdly__sid_fx__DOT__pa;
    vlSelf->sid_fx__DOT__pb = __Vdly__sid_fx__DOT__pb;
    vlSelf->sid_fx__DOT__fq_wait = __Vdly__sid_fx__DOT__fq_wait;
    vlSelf->sid_fx__DOT__rl = __Vdly__sid_fx__DOT__rl;
    vlSelf->sid_fx__DOT__rr = __Vdly__sid_fx__DOT__rr;
    vlSelf->sid_fx__DOT__fetch = __Vdly__sid_fx__DOT__fetch;
    vlSelf->sid_fx__DOT__fetch2 = __Vdly__sid_fx__DOT__fetch2;
    vlSelf->sid_fx__DOT__pa_a = __Vdly__sid_fx__DOT__pa_a;
    vlSelf->sid_fx__DOT__pa_d = __Vdly__sid_fx__DOT__pa_d;
    vlSelf->sid_fx__DOT__wp = __Vdly__sid_fx__DOT__wp;
    vlSelf->sid_fx__DOT__tl_v = __Vdly__sid_fx__DOT__tl_v;
    vlSelf->sid_fx__DOT__tr_v = __Vdly__sid_fx__DOT__tr_v;
    vlSelf->sid_fx__DOT__tl = __Vdly__sid_fx__DOT__tl;
    vlSelf->sid_fx__DOT__tr = __Vdly__sid_fx__DOT__tr;
    sid_fx__DOT__fq = ((2U >= (IData)(vlSelf->sid_fx__DOT__pv))
                        ? vlSelf->sid_fx__DOT__freq
                       [vlSelf->sid_fx__DOT__pv] : 0U);
    vlSelf->sid_fx__DOT__due_l = ((IData)(vlSelf->sid_fx__DOT__tl_v) 
                                  & (0x222e0U <= (0xfffffU 
                                                  & (vlSelf->sid_fx__DOT__now 
                                                     - (IData)(
                                                               (vlSelf->sid_fx__DOT__tl 
                                                                >> 0xdU))))));
    vlSelf->sid_fx__DOT__due_r = ((IData)(vlSelf->sid_fx__DOT__tr_v) 
                                  & (0x30d40U <= (0xfffffU 
                                                  & (vlSelf->sid_fx__DOT__now 
                                                     - (IData)(
                                                               (vlSelf->sid_fx__DOT__tr 
                                                                >> 0xdU))))));
    vlSelf->sid_fx__DOT__rq = vlSelf->sid_fx__DOT__ring__DOT__m
        [vlSelf->sid_fx__DOT__ra];
    vlSelf->sid_fx__DOT__sharp = (0xffffU & ((IData)(sid_fx__DOT__fq) 
                                             + (VL_SHIFTR_III(16,16,32, (IData)(sid_fx__DOT__fq), 8U) 
                                                + VL_SHIFTR_III(16,16,32, (IData)(sid_fx__DOT__fq), 9U))));
    vlSelf->sid_fx__DOT__ra = __Vdly__sid_fx__DOT__ra;
    if (__VdlySet__sid_fx__DOT__ring__DOT__m__v0) {
        vlSelf->sid_fx__DOT__ring__DOT__m[__VdlyDim0__sid_fx__DOT__ring__DOT__m__v0] 
            = __VdlyVal__sid_fx__DOT__ring__DOT__m__v0;
    }
}

void Vsid_fx___024root___eval_triggers__act(Vsid_fx___024root* vlSelf);

bool Vsid_fx___024root___eval_phase__act(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_phase__act\n"); );
    // Init
    VlTriggerVec<1> __VpreTriggered;
    CData/*0:0*/ __VactExecute;
    // Body
    Vsid_fx___024root___eval_triggers__act(vlSelf);
    __VactExecute = vlSelf->__VactTriggered.any();
    if (__VactExecute) {
        __VpreTriggered.andNot(vlSelf->__VactTriggered, vlSelf->__VnbaTriggered);
        vlSelf->__VnbaTriggered.thisOr(vlSelf->__VactTriggered);
        Vsid_fx___024root___eval_act(vlSelf);
    }
    return (__VactExecute);
}

bool Vsid_fx___024root___eval_phase__nba(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_phase__nba\n"); );
    // Init
    CData/*0:0*/ __VnbaExecute;
    // Body
    __VnbaExecute = vlSelf->__VnbaTriggered.any();
    if (__VnbaExecute) {
        Vsid_fx___024root___eval_nba(vlSelf);
        vlSelf->__VnbaTriggered.clear();
    }
    return (__VnbaExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__ico(Vsid_fx___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__nba(Vsid_fx___024root* vlSelf);
#endif  // VL_DEBUG
#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__act(Vsid_fx___024root* vlSelf);
#endif  // VL_DEBUG

void Vsid_fx___024root___eval(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval\n"); );
    // Init
    IData/*31:0*/ __VicoIterCount;
    CData/*0:0*/ __VicoContinue;
    IData/*31:0*/ __VnbaIterCount;
    CData/*0:0*/ __VnbaContinue;
    // Body
    __VicoIterCount = 0U;
    vlSelf->__VicoFirstIteration = 1U;
    __VicoContinue = 1U;
    while (__VicoContinue) {
        if (VL_UNLIKELY((0x64U < __VicoIterCount))) {
#ifdef VL_DEBUG
            Vsid_fx___024root___dump_triggers__ico(vlSelf);
#endif
            VL_FATAL_MT("../../rtl/octovic/sid_fx.sv", 8, "", "Input combinational region did not converge.");
        }
        __VicoIterCount = ((IData)(1U) + __VicoIterCount);
        __VicoContinue = 0U;
        if (Vsid_fx___024root___eval_phase__ico(vlSelf)) {
            __VicoContinue = 1U;
        }
        vlSelf->__VicoFirstIteration = 0U;
    }
    __VnbaIterCount = 0U;
    __VnbaContinue = 1U;
    while (__VnbaContinue) {
        if (VL_UNLIKELY((0x64U < __VnbaIterCount))) {
#ifdef VL_DEBUG
            Vsid_fx___024root___dump_triggers__nba(vlSelf);
#endif
            VL_FATAL_MT("../../rtl/octovic/sid_fx.sv", 8, "", "NBA region did not converge.");
        }
        __VnbaIterCount = ((IData)(1U) + __VnbaIterCount);
        __VnbaContinue = 0U;
        vlSelf->__VactIterCount = 0U;
        vlSelf->__VactContinue = 1U;
        while (vlSelf->__VactContinue) {
            if (VL_UNLIKELY((0x64U < vlSelf->__VactIterCount))) {
#ifdef VL_DEBUG
                Vsid_fx___024root___dump_triggers__act(vlSelf);
#endif
                VL_FATAL_MT("../../rtl/octovic/sid_fx.sv", 8, "", "Active region did not converge.");
            }
            vlSelf->__VactIterCount = ((IData)(1U) 
                                       + vlSelf->__VactIterCount);
            vlSelf->__VactContinue = 0U;
            if (Vsid_fx___024root___eval_phase__act(vlSelf)) {
                vlSelf->__VactContinue = 1U;
            }
        }
        if (Vsid_fx___024root___eval_phase__nba(vlSelf)) {
            __VnbaContinue = 1U;
        }
    }
}

#ifdef VL_DEBUG
void Vsid_fx___024root___eval_debug_assertions(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_debug_assertions\n"); );
    // Body
    if (VL_UNLIKELY((vlSelf->clk & 0xfeU))) {
        Verilated::overWidthError("clk");}
    if (VL_UNLIKELY((vlSelf->reset & 0xfeU))) {
        Verilated::overWidthError("reset");}
    if (VL_UNLIKELY((vlSelf->ce_1m & 0xfeU))) {
        Verilated::overWidthError("ce_1m");}
    if (VL_UNLIKELY((vlSelf->mode & 0xfcU))) {
        Verilated::overWidthError("mode");}
    if (VL_UNLIKELY((vlSelf->cpu_wr & 0xfeU))) {
        Verilated::overWidthError("cpu_wr");}
    if (VL_UNLIKELY((vlSelf->sid1_wr & 0xfeU))) {
        Verilated::overWidthError("sid1_wr");}
    if (VL_UNLIKELY((vlSelf->addr & 0xe0U))) {
        Verilated::overWidthError("addr");}
    if (VL_UNLIKELY((vlSelf->busy1 & 0xfeU))) {
        Verilated::overWidthError("busy1");}
    if (VL_UNLIKELY((vlSelf->busy2 & 0xfeU))) {
        Verilated::overWidthError("busy2");}
}
#endif  // VL_DEBUG
