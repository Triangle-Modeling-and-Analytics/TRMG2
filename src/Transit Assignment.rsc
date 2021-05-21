/*

*/

Macro "Transit Assignment" (Args)

    RunMacro("Run Transit Assignment", Args)
    RunMacro("Aggregate Transit Assignment Results", Args)
    return(1)
endmacro

/*

*/

Macro "Run Transit Assignment" (Args)

    rts_file = Args.Routes
    out_dir = Args.[Output Folder]
    net_dir = out_dir + "/networks"
    assn_dir = out_dir + "/assignment/transit"

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

/*
Transit assignment creates many output files when run for multiple networks.
This is a helper macro to collapse them together into CSV files.
*/

Macro "Aggregate Transit Assignment Results" (Args)

    out_dir = Args.[Output Folder]
    net_dir = out_dir + "/networks"
    assn_dir = out_dir + "/assignment/transit"
    periods = Args.periods

    transit_nets = RunMacro("Catalog Files", net_dir, "tnw")
    suffixes = {"", "_linkflow", "_onoff", "_walkflow"}

    // Add fields to individual files
    for net in transit_nets do
        {, , name, } = SplitPath(net)
        name = Substitute(name, "tnet_", "", )
        name = Substitute(name, ".tnw", "", )
        // TODO: this is only needed because the OBS didn't have any of these
        // remove it once done assigning the OBS
        if name = "NT_knr_eb" then continue
        {tod, access, mode} = ParseString(name, "_")

        for suffix in suffixes do
            file = assn_dir + "/" + name + suffix + ".bin"
            vw = OpenTable("vw", "FFB", {file})
            a_fields =  {
                {"tod", "Character", 10,,,,, },
                {"access", "Character", 10,,,,, },
                {"mode", "Character", 10,,,,, }
            }
            RunMacro("Add Fields", {view: vw, a_fields: a_fields})
            num_rows = GetRecordCount(vw, )
            data.tod = Vector(num_rows, "String", {Constant: tod})
            data.access = Vector(num_rows, "String", {Constant: access})
            data.mode = Vector(num_rows, "String", {Constant: mode})
            SetDataVectors(vw + "|", data, )
            if suffix = ""
                then tables.(tod).flow = tables.(tod).flow + {file}
                else tables.(tod).(suffix) = tables.(tod).(suffix) + {file}
            CloseView(vw)
        end
    end

    // Concatenate files together by period
    for period in periods do
        a = tables.(period)
        for suffix in suffixes do
            if suffix = "" then do
                files = a.flow
                dest_file = assn_dir + "/" + period + "_flow.csv" 
            end else do
                files = a.(suffix)
                dest_file = assn_dir + "/" + period + suffix + ".csv" 
            end

            for i = 1 to files.length do
                file = files[i]
                if i = 1 then df = CreateObject("df", file)
                else do
                    df2 = CreateObject("df", file)
                    df.bind_rows(df2)
                end
            end
            df.write_csv(dest_file)
        end
    end

EndMacro