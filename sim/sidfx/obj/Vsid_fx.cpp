// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Model implementation (design independent parts)

#include "Vsid_fx__pch.h"

//============================================================
// Constructors

Vsid_fx::Vsid_fx(VerilatedContext* _vcontextp__, const char* _vcname__)
    : VerilatedModel{*_vcontextp__}
    , vlSymsp{new Vsid_fx__Syms(contextp(), _vcname__, this)}
    , clk{vlSymsp->TOP.clk}
    , reset{vlSymsp->TOP.reset}
    , ce_1m{vlSymsp->TOP.ce_1m}
    , mode{vlSymsp->TOP.mode}
    , cpu_wr{vlSymsp->TOP.cpu_wr}
    , sid1_wr{vlSymsp->TOP.sid1_wr}
    , addr{vlSymsp->TOP.addr}
    , data{vlSymsp->TOP.data}
    , busy1{vlSymsp->TOP.busy1}
    , busy2{vlSymsp->TOP.busy2}
    , inj_we{vlSymsp->TOP.inj_we}
    , inj_tgt{vlSymsp->TOP.inj_tgt}
    , inj_addr{vlSymsp->TOP.inj_addr}
    , inj_data{vlSymsp->TOP.inj_data}
    , rootp{&(vlSymsp->TOP)}
{
    // Register model with the context
    contextp()->addModel(this);
}

Vsid_fx::Vsid_fx(const char* _vcname__)
    : Vsid_fx(Verilated::threadContextp(), _vcname__)
{
}

//============================================================
// Destructor

Vsid_fx::~Vsid_fx() {
    delete vlSymsp;
}

//============================================================
// Evaluation function

#ifdef VL_DEBUG
void Vsid_fx___024root___eval_debug_assertions(Vsid_fx___024root* vlSelf);
#endif  // VL_DEBUG
void Vsid_fx___024root___eval_static(Vsid_fx___024root* vlSelf);
void Vsid_fx___024root___eval_initial(Vsid_fx___024root* vlSelf);
void Vsid_fx___024root___eval_settle(Vsid_fx___024root* vlSelf);
void Vsid_fx___024root___eval(Vsid_fx___024root* vlSelf);

void Vsid_fx::eval_step() {
    VL_DEBUG_IF(VL_DBG_MSGF("+++++TOP Evaluate Vsid_fx::eval_step\n"); );
#ifdef VL_DEBUG
    // Debug assertions
    Vsid_fx___024root___eval_debug_assertions(&(vlSymsp->TOP));
#endif  // VL_DEBUG
    vlSymsp->__Vm_deleter.deleteAll();
    if (VL_UNLIKELY(!vlSymsp->__Vm_didInit)) {
        vlSymsp->__Vm_didInit = true;
        VL_DEBUG_IF(VL_DBG_MSGF("+ Initial\n"););
        Vsid_fx___024root___eval_static(&(vlSymsp->TOP));
        Vsid_fx___024root___eval_initial(&(vlSymsp->TOP));
        Vsid_fx___024root___eval_settle(&(vlSymsp->TOP));
    }
    VL_DEBUG_IF(VL_DBG_MSGF("+ Eval\n"););
    Vsid_fx___024root___eval(&(vlSymsp->TOP));
    // Evaluate cleanup
    Verilated::endOfEval(vlSymsp->__Vm_evalMsgQp);
}

//============================================================
// Events and timing
bool Vsid_fx::eventsPending() { return false; }

uint64_t Vsid_fx::nextTimeSlot() {
    VL_FATAL_MT(__FILE__, __LINE__, "", "%Error: No delays in the design");
    return 0;
}

//============================================================
// Utilities

const char* Vsid_fx::name() const {
    return vlSymsp->name();
}

//============================================================
// Invoke final blocks

void Vsid_fx___024root___eval_final(Vsid_fx___024root* vlSelf);

VL_ATTR_COLD void Vsid_fx::final() {
    Vsid_fx___024root___eval_final(&(vlSymsp->TOP));
}

//============================================================
// Implementations of abstract methods from VerilatedModel

const char* Vsid_fx::hierName() const { return vlSymsp->name(); }
const char* Vsid_fx::modelName() const { return "Vsid_fx"; }
unsigned Vsid_fx::threads() const { return 1; }
void Vsid_fx::prepareClone() const { contextp()->prepareClone(); }
void Vsid_fx::atClone() const {
    contextp()->threadPoolpOnClone();
}
