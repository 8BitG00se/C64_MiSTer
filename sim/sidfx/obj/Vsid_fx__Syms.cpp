// Verilated -*- C++ -*-
// DESCRIPTION: Verilator output: Symbol table implementation internals

#include "Vsid_fx__pch.h"
#include "Vsid_fx.h"
#include "Vsid_fx___024root.h"

// FUNCTIONS
Vsid_fx__Syms::~Vsid_fx__Syms()
{
}

Vsid_fx__Syms::Vsid_fx__Syms(VerilatedContext* contextp, const char* namep, Vsid_fx* modelp)
    : VerilatedSyms{contextp}
    // Setup internal state of the Syms class
    , __Vm_modelp{modelp}
    // Setup module instances
    , TOP{this, namep}
{
        // Check resources
        Verilated::stackCheck(155);
    // Configure time unit / time precision
    _vm_contextp__->timeunit(-12);
    _vm_contextp__->timeprecision(-12);
    // Setup each module's pointers to their submodules
    // Setup each module's pointer back to symbol table (for public functions)
    TOP.__Vconfigure(true);
}
