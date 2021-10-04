/*

*/

Macro "Transit Assignment" (Args)

    RunMacro("Create Transit Matrices", Args)
    RunMacro("Run Transit Assignment", Args)
    // TODO: update this macro
    // RunMacro("Aggregate Transit Assignment Results", Args)
    return(1)
endmacro

/*
TODO: need to update once we see what the NHB matrices look like
*/

Macro "Create Transit Matrices" (Args)

    trn_dir = Args.[Output Folder] + "/assignment/transit"
    // TODO: change this to resident/trip_matrices everwhere
    trip_dir = Args.[Output Folder] + "/resident/trip_tables"
    nhb_dir = Args.[Output Folder] + "/resident/nhb//dc/trip_matrices"
    periods = Args.periods

    access_modes = {"w", "pnr", "knr"}
    files = RunMacro("Catalog Files", trip_dir, "mtx")

    // Create a starting transit matrix for each time period
    for period in periods do
        out_file = trn_dir + "/transit_" + period + ".mtx"
        CopyFile(files[1], out_file)
        mtx = CreateObject("Matrix", out_file)
        core_names = mtx.GetCoreNames()
        mtx.AddCores({"temp"})
        mtx.DropCores(core_names)
        mtxs.(period) = mtx
    end

    // Collapse the resident matrices
    for file in files do
        {, , name, } = SplitPath(file)
        period = Right(name, 2)
        out_mtx = mtxs.(period)
        
        trip_mtx = CreateObject("Matrix", file)
        core_names = trip_mtx.GetCoreNames()
        for core_name in core_names do
            parts = ParseString(core_name, "_")
            access_mode = parts[1]
            // skip non-transit cores
            if access_modes.position(access_mode) = 0 then continue
            // initialize core if it doesn't exist
            out_core_names = out_mtx.GetCoreNames()
            if out_core_names.position(core_name) = 0 then do
                out_mtx.AddCores({core_name})
                out_core = out_mtx.GetCore(core_name)
                out_core := 0
            end
            out_core = out_mtx.GetCore(core_name)
            trip_core = trip_mtx.GetCore(core_name)
            out_core := out_core + nz(trip_core)
        end

        out_mtx.DropCores({"temp"})
        mtxs.(period) = out_mtx
    end

    // Add in airport transit trips
    air_dir = Args.[Output Folder] + "/airport"
    for period in periods do
        out_mtx = mtxs.(period)
        air_mtx_file = air_dir + "/airport_transit_trips_" + period + ".mtx"

        air_mtx = CreateObject("Matrix", air_mtx_file)
        core_names = air_mtx.GetCoreNames()
        for core_name in core_names do
            out_core = out_mtx.GetCore(core_name)
            air_core = air_mtx.GetCore(core_name)
            out_core := nz(out_core) + nz(air_core)
        end

        mtxs.(period) = out_mtx
    end

    // NHB Trips
    for period in periods do
        nhb_mtx_file = nhb_dir + "/NHB_transit_" + period + ".mtx"
        nhb_mtx = CreateObject("Matrix", nhb_mtx_file)
        nhb_core = nhb_mtx.GetCore("Total")

        trn_mtx_file = trn_dir + "/transit_" + period + ".mtx"
        trn_mtx = CreateObject("Matrix", trn_mtx_file)
        trn_mtx.AddCores({"w_all"})
        trn_core = trn_mtx.GetCore("w_all")
        trn_core := nz(trn_core) + nz(nhb_core)
    end

    //TODO: add university transit trips
endmacro

/*

*/

Macro "Run Transit Assignment" (Args)

    rts_file = Args.Routes
    out_dir = Args.[Output Folder]
    net_dir = out_dir + "/networks"
    assn_dir = out_dir + "/assignment/transit"
    periods = Args.periods

    for period in periods do
        mtx_file = assn_dir + "/transit_" + period + ".mtx"
        mtx = CreateObject("Matrix", mtx_file)
        core_names = mtx.GetCoreNames()
        for core_name in core_names do
            net_file = net_dir + "/tnet_" + period + "_" + core_name + ".tnw"

            o = CreateObject(
                "Network.PublicTransportAssignment",
                {RS: rts_file, NetworkName: net_file}
            )
            name = period + "_" + core_name
            o.FlowTable = assn_dir + "/" + name + ".bin"
            o.OnOffTable = assn_dir + "/" + name + "_onoff.bin"
            o.TransitLinkFlowsTable = assn_dir + "/" + name + "_linkflow.bin"
            o.WalkFlowTable = assn_dir + "/" + name + "_walkflow.bin"
            o.DemandMatrix({
                MatrixFile: mtx_file,
                Matrix: core_name
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
