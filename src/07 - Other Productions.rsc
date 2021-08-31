/*
This macro is used by the flow chart to call the production macros for 
non-residential markets. See their RSC files for the actual macros 
(e.g. Airport.rsc)
*/

Macro "Other Productions" (Args)
    RunMacro("Airport Production", Args)
    return(1)
endmacro