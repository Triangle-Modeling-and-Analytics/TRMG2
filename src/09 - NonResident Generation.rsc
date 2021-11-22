/*
This macro is used by the flow chart to call the production macros for 
non-residential markets. See their RSC files for the actual macros 
(e.g. Airport.rsc)
*/

Macro "NonResident Generation" (Args)
    RunMacro("Airport", Args)
    RunMacro("External", Args)
    RunMacro("IEEI", Args)
    RunMacro("CV Productions/Attractions", Args)
    RunMacro("CV TOD", Args)
    RunMacro("University Productions", Args)
    RunMacro("University Attractions", Args)
    RunMacro("University Balance Ps and As", Args)
    RunMacro("University TOD", Args)
    return(1)
endmacro