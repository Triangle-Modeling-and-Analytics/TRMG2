/*

*/

Macro "Transit Assignment" (Args)

    // RunMacro("Run Transit Assignment", Args)
    return(1)
endmacro

/*

*/

Macro "Run Transit Assignment" (Args)

    out_dir = Args.[Output Folder]
    net_dir = out_dir + "\\networks"
    // mtx_dir = 

    transit_nets = RunMacro("Catalog Files", net_dir, "tnw")

    for net in transit_nets do

    end

endmacro