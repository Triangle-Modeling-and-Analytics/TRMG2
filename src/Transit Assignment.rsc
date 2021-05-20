/*

*/

Macro "Transit Assignment" (Args)

    RunMacro("Run Transit Assignment", Args)
    return(1)
endmacro

/*

*/

Macro "Run Transit Assignment" (Args)

    rts_file = Args.Routes
    out_dir = Args.[Output Folder]
    net_dir = out_dir + "/networks"
    assn_dir = out_dir + "/assignment/transit"
    // mtx_dir = 

    transit_nets = RunMacro("Catalog Files", net_dir, "tnw")

    for net in transit_nets do
        {, , name, } = SplitPath(net)
        name = Substitute(name, "tnet_", "", )
        name = Substitute(name, ".tnw", "", )

        o = CreateObject("Network.PublicTransportAssignment", {RS: rts_file, NetworkName: net})
        o.FlowTable = assn_dir + "/" + name + ".bin"
        o.OnOffTable = assn_dir + "/" + name + "_onoff.bin"
        o.TransitLinkFlowsTable = assn_dir + "/" + name + "_linkflow.bin"
        o.WalkFlowTable = assn_dir + "/" + name + "_walkflow.bin"
        mtx_file = assn_dir + "/" + "obs_" + name + ".mtx" // TODO: change this to final file name
        // TODO: this exist check is only for assigning the obs. Remove.
        if GetFileInfo(mtx_file) <> null then do
            o.DemandMatrix({
                MatrixFile: mtx_file,
                Matrix: "weight"
            })
            o.Run()
        end
    end

endmacro