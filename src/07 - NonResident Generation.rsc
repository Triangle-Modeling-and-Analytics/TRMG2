/*
This macro is used by the flow chart to call the production macros for 
non-residential markets. See their RSC files for the actual macros 
(e.g. Airport.rsc)
*/

Macro "NonResident Generation" (Args)
    RunMacro("Airport", Args)
    RunMacro("CV Productions/Attractions", Args)
    RunMacro("CV TOD", Args)
    return(1)
endmacro