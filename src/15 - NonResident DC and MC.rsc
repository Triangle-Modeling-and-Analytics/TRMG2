/*

*/

Macro "Airport MC" (Args)
    RunMacro("Airport Mode Choice", Args)
    RunMacro("Airport Separate Auto and Transit", Args)
    RunMacro("Airport Directionality", Args)
    return(1)
endmacro

Macro "Commercial Vehicles DC" (Args)
    RunMacro("CV Gravity", Args)
    return(1)
endmacro