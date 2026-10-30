// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Design implementation internals
// See Vsid_fx.h for the primary calling header

#include "Vsid_fx__pch.h"
#include "Vsid_fx___024root.h"

VL_ATTR_COLD void Vsid_fx___024root___eval_static(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_static\n"); );
}

VL_ATTR_COLD void Vsid_fx___024root___eval_initial(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_initial\n"); );
    // Body
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = vlSelf->clk;
}

VL_ATTR_COLD void Vsid_fx___024root___eval_final(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_final\n"); );
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__stl(Vsid_fx___024root* vlSelf);
#endif  // VL_DEBUG
VL_ATTR_COLD bool Vsid_fx___024root___eval_phase__stl(Vsid_fx___024root* vlSelf);

VL_ATTR_COLD void Vsid_fx___024root___eval_settle(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_settle\n"); );
    // Init
    IData/*31:0*/ __VstlIterCount;
    CData/*0:0*/ __VstlContinue;
    // Body
    __VstlIterCount = 0U;
    vlSelf->__VstlFirstIteration = 1U;
    __VstlContinue = 1U;
    while (__VstlContinue) {
        if (VL_UNLIKELY((0x64U < __VstlIterCount))) {
#ifdef VL_DEBUG
            Vsid_fx___024root___dump_triggers__stl(vlSelf);
#endif
            VL_FATAL_MT("../../rtl/octovic/sid_fx.sv", 8, "", "Settle region did not converge.");
        }
        __VstlIterCount = ((IData)(1U) + __VstlIterCount);
        __VstlContinue = 0U;
        if (Vsid_fx___024root___eval_phase__stl(vlSelf)) {
            __VstlContinue = 1U;
        }
        vlSelf->__VstlFirstIteration = 0U;
    }
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__stl(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___dump_triggers__stl\n"); );
    // Body
    if ((1U & (~ vlSelf->__VstlTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VstlTriggered.word(0U))) {
        VL_DBG_MSGF("         'stl' region trigger index 0 is active: Internal 'stl' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vsid_fx___024root___stl_sequent__TOP__0(Vsid_fx___024root* vlSelf);

VL_ATTR_COLD void Vsid_fx___024root___eval_stl(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_stl\n"); );
    // Body
    if ((1ULL & vlSelf->__VstlTriggered.word(0U))) {
        Vsid_fx___024root___stl_sequent__TOP__0(vlSelf);
    }
}

VL_ATTR_COLD void Vsid_fx___024root___stl_sequent__TOP__0(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___stl_sequent__TOP__0\n"); );
    // Init
    SData/*15:0*/ sid_fx__DOT__fq;
    sid_fx__DOT__fq = 0;
    // Body
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
    sid_fx__DOT__fq = ((2U >= (IData)(vlSelf->sid_fx__DOT__pv))
                        ? vlSelf->sid_fx__DOT__freq
                       [vlSelf->sid_fx__DOT__pv] : 0U);
    vlSelf->sid_fx__DOT__vo = ((7U > (IData)(vlSelf->addr))
                                ? 0U : ((0xeU > (IData)(vlSelf->addr))
                                         ? 1U : 2U));
    vlSelf->sid_fx__DOT__sharp = (0xffffU & ((IData)(sid_fx__DOT__fq) 
                                             + (VL_SHIFTR_III(16,16,32, (IData)(sid_fx__DOT__fq), 8U) 
                                                + VL_SHIFTR_III(16,16,32, (IData)(sid_fx__DOT__fq), 9U))));
    vlSelf->sid_fx__DOT__vb = ((0U == (IData)(vlSelf->sid_fx__DOT__vo))
                                ? 0U : ((1U == (IData)(vlSelf->sid_fx__DOT__vo))
                                         ? 7U : 0xeU));
    vlSelf->sid_fx__DOT__is_freq = ((0x15U > (IData)(vlSelf->addr)) 
                                    & (2U > (0x1fU 
                                             & ((IData)(vlSelf->addr) 
                                                - (IData)(vlSelf->sid_fx__DOT__vb)))));
}

VL_ATTR_COLD void Vsid_fx___024root___eval_triggers__stl(Vsid_fx___024root* vlSelf);

VL_ATTR_COLD bool Vsid_fx___024root___eval_phase__stl(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___eval_phase__stl\n"); );
    // Init
    CData/*0:0*/ __VstlExecute;
    // Body
    Vsid_fx___024root___eval_triggers__stl(vlSelf);
    __VstlExecute = vlSelf->__VstlTriggered.any();
    if (__VstlExecute) {
        Vsid_fx___024root___eval_stl(vlSelf);
    }
    return (__VstlExecute);
}

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__ico(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___dump_triggers__ico\n"); );
    // Body
    if ((1U & (~ vlSelf->__VicoTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VicoTriggered.word(0U))) {
        VL_DBG_MSGF("         'ico' region trigger index 0 is active: Internal 'ico' trigger - first iteration\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__act(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___dump_triggers__act\n"); );
    // Body
    if ((1U & (~ vlSelf->__VactTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VactTriggered.word(0U))) {
        VL_DBG_MSGF("         'act' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

#ifdef VL_DEBUG
VL_ATTR_COLD void Vsid_fx___024root___dump_triggers__nba(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___dump_triggers__nba\n"); );
    // Body
    if ((1U & (~ vlSelf->__VnbaTriggered.any()))) {
        VL_DBG_MSGF("         No triggers active\n");
    }
    if ((1ULL & vlSelf->__VnbaTriggered.word(0U))) {
        VL_DBG_MSGF("         'nba' region trigger index 0 is active: @(posedge clk)\n");
    }
}
#endif  // VL_DEBUG

VL_ATTR_COLD void Vsid_fx___024root___ctor_var_reset(Vsid_fx___024root* vlSelf) {
    (void)vlSelf;  // Prevent unused variable warning
    Vsid_fx__Syms* const __restrict vlSymsp VL_ATTR_UNUSED = vlSelf->vlSymsp;
    VL_DEBUG_IF(VL_DBG_MSGF("+    Vsid_fx___024root___ctor_var_reset\n"); );
    // Body
    vlSelf->clk = VL_RAND_RESET_I(1);
    vlSelf->reset = VL_RAND_RESET_I(1);
    vlSelf->ce_1m = VL_RAND_RESET_I(1);
    vlSelf->mode = VL_RAND_RESET_I(2);
    vlSelf->cpu_wr = VL_RAND_RESET_I(1);
    vlSelf->sid1_wr = VL_RAND_RESET_I(1);
    vlSelf->addr = VL_RAND_RESET_I(5);
    vlSelf->data = VL_RAND_RESET_I(8);
    vlSelf->busy1 = VL_RAND_RESET_I(1);
    vlSelf->busy2 = VL_RAND_RESET_I(1);
    vlSelf->inj_we = VL_RAND_RESET_I(1);
    vlSelf->inj_tgt = VL_RAND_RESET_I(2);
    vlSelf->inj_addr = VL_RAND_RESET_I(5);
    vlSelf->inj_data = VL_RAND_RESET_I(8);
    vlSelf->sid_fx__DOT__now = VL_RAND_RESET_I(20);
    for (int __Vi0 = 0; __Vi0 < 3; ++__Vi0) {
        vlSelf->sid_fx__DOT__freq[__Vi0] = VL_RAND_RESET_I(16);
    }
    vlSelf->sid_fx__DOT__vo = VL_RAND_RESET_I(2);
    vlSelf->sid_fx__DOT__vb = VL_RAND_RESET_I(5);
    vlSelf->sid_fx__DOT__is_freq = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__pa = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__pb = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__pa_a = VL_RAND_RESET_I(5);
    vlSelf->sid_fx__DOT__pb_a = VL_RAND_RESET_I(5);
    vlSelf->sid_fx__DOT__pa_d = VL_RAND_RESET_I(8);
    vlSelf->sid_fx__DOT__pv = VL_RAND_RESET_I(2);
    vlSelf->sid_fx__DOT__sharp = VL_RAND_RESET_I(16);
    vlSelf->sid_fx__DOT__fq_wait = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__wp = VL_RAND_RESET_I(11);
    vlSelf->sid_fx__DOT__rl = VL_RAND_RESET_I(11);
    vlSelf->sid_fx__DOT__rr = VL_RAND_RESET_I(11);
    vlSelf->sid_fx__DOT__ra = VL_RAND_RESET_I(11);
    vlSelf->sid_fx__DOT__rq = VL_RAND_RESET_Q(33);
    vlSelf->sid_fx__DOT__tl = VL_RAND_RESET_Q(33);
    vlSelf->sid_fx__DOT__tr = VL_RAND_RESET_Q(33);
    vlSelf->sid_fx__DOT__tl_v = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__tr_v = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__fetch = VL_RAND_RESET_I(2);
    vlSelf->sid_fx__DOT__fetch2 = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__due_l = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT__due_r = VL_RAND_RESET_I(1);
    vlSelf->sid_fx__DOT____Vlvbound_hea9e1deb__0 = VL_RAND_RESET_I(8);
    vlSelf->sid_fx__DOT____Vlvbound_heaa5aae3__0 = VL_RAND_RESET_I(8);
    for (int __Vi0 = 0; __Vi0 < 2048; ++__Vi0) {
        vlSelf->sid_fx__DOT__ring__DOT__m[__Vi0] = VL_RAND_RESET_Q(33);
    }
    vlSelf->__Vtrigprevexpr___TOP__clk__0 = VL_RAND_RESET_I(1);
}
