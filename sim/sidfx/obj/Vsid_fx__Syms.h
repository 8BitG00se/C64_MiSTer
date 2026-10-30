// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table internal header
//
// Internal details; most calling programs do not need this header,
// unless using verilator public meta comments.

#ifndef VERILATED_VSID_FX__SYMS_H_
#define VERILATED_VSID_FX__SYMS_H_  // guard

#include "verilated.h"

// INCLUDE MODEL CLASS

#include "Vsid_fx.h"

// INCLUDE MODULE CLASSES
#include "Vsid_fx___024root.h"

// SYMS CLASS (contains all model state)
class alignas(VL_CACHE_LINE_BYTES)Vsid_fx__Syms final : public VerilatedSyms {
  public:
    // INTERNAL STATE
    Vsid_fx* const __Vm_modelp;
    VlDeleter __Vm_deleter;
    bool __Vm_didInit = false;

    // MODULE INSTANCE STATE
    Vsid_fx___024root              TOP;

    // CONSTRUCTORS
    Vsid_fx__Syms(VerilatedContext* contextp, const char* namep, Vsid_fx* modelp);
    ~Vsid_fx__Syms();

    // METHODS
    const char* name() { return TOP.name(); }
};

#endif  // guard
