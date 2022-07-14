/*

*/

Macro "Create Transit Matrices" (Args)
    RunMacro("Create Transit Matrices2", Args)
    RunMacro("Flip Transit Matrices", Args)
    return(1)
endmacro

Macro "Run Transit Assignment" (Args)
    RunMacro("Transit Assignment", Args)
    return(1)
endmacro

/*

*/

Macro "Create Transit Matrices2" (Args)

    trn_dir = Args.[Output Folder] + "/assignment/transit"
    trip_dir = Args.[Output Folder] + "/resident/trip_matrices"
    nhb_dir = Args.[Output Folder] + "/resident/nhb//dc/trip_matrices"
    periods = Args.periods
    access_modes = Args.access_modes

    files = RunMacro("Catalog Files", {dir: trip_dir, ext: "mtx"})

    // Create a starting transit matrix for each time period
    for period in periods do
        out_file = trn_dir + "/transit_" + period + ".mtx"
        CopyFile(files[1], out_file)
        mtx = CreateObject("Matrix", out_file)
        RenameMatrix(mtx.GetMatrixHandle(), "Trips")
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

    //Add in university trips
    univ_dir = Args.[Output Folder] + "/university"
    for period in periods do
        out_mtx = mtxs.(period)

        univ_mtx_file = univ_dir + "/university_trips_" + period + ".mtx"
        univ_mtx = CreateObject("Matrix", univ_mtx_file)

        // Add w_lb and pnr_lb cores to the assignment matrix
        // Note: while the other cores in the university matrix are OD, the transit
        // cores are still PA, so they can be added here correctly.
        univ_core = univ_mtx.GetCore("w_lb")
        out_core = out_mtx.GetCore("w_lb")
        out_core := nz(out_core) + nz(univ_core)
        univ_core = univ_mtx.GetCore("pnr_lb")
        out_core = out_mtx.GetCore("pnr_lb")
        out_core := nz(out_core) + nz(univ_core)

        mtxs.(period) = out_mtx
    end

    // Add external transit trips
    ieei_file = Args.[Input Folder] + "/external/ieei_transit.csv"
    access_modes = {"pnr", "knr"}
    modes = {"lb", "eb"}
    vw = OpenTable("ieei", "CSV", {ieei_file})
    in_file = trn_dir + "/transit_" + periods[1] + ".mtx"
    temp_mtx_file = trn_dir + "/temp.mtx"
    CopyFile(in_file, temp_mtx_file)
    temp_mtx = CreateObject("Matrix", temp_mtx_file)
    cores_to_drop = temp_mtx.GetCoreNames()
    for period in periods do
        for mode in modes do
            for access_mode in access_modes do
                field_name = access_mode + "_" + mode + "_" + period
                fields = fields + {field_name}
                temp_mtx.AddCores(field_name)
            end
        end
    end
    temp_mtx.DropCores(cores_to_drop)
    mh = temp_mtx.GetMatrixHandle()
    UpdateMatrixFromView(
        mh, vw + "|", "From", "To", null, 
        fields,
        "Add", 
        {"Missing is zero": "Yes"}
    )
    CloseView(vw)
    for period in periods do
        out_mtx = mtxs.(period)

        for mode in modes do
            for access_mode in access_modes do
                out_core = out_mtx.GetCore(access_mode + "_" + mode)
                temp_core = temp_mtx.GetCore(access_mode + "_" + mode + "_" + period)
                out_core := nz(out_core) + nz(temp_core)
            end
        end
    end

    temp_mtx = null
    mh = null
    temp_core = null
    DeleteFile(temp_mtx_file)
endmacro

/*
Applies rough directionality to transit by time period.

AM: stays in PA format
PM: flips to AP format
MD/NT: (PA + AP) / 2
*/

Macro "Flip Transit Matrices" (Args)
    
    trn_dir = Args.[Output Folder] + "/assignment/transit"
    periods = Args.periods

    for period in periods do
        
        // Don't modify the AM period
        if period = "AM" then continue

        out_file = trn_dir + "/transit_" + period + ".mtx"
        
        if period = "PM" then do
            RunMacro("Transpose Matrix", out_file, "PM transit trips flipped to AP")
        end

        if period = "MD" or period = "NT" then do
            t_file = Substitute(out_file, ".mtx", "_t.mtx", )
            CopyFile(out_file, t_file)
            RunMacro("Transpose Matrix", t_file, "temp transposed matrix")
            out_mtx = CreateObject("Matrix", out_file)
            core_names = out_mtx.GetCoreNames()
            t_mtx = CreateObject("Matrix", t_file)
            for core_name in core_names do
                out_core = out_mtx.GetCore(core_name)
                t_core = t_mtx.GetCore(core_name)
                out_core := (out_core + t_core) / 2
            end
            t_core = null
            t_mtx = null
            DeleteFile(t_file)
        end
    end
endmacro

/*

*/

Macro "Transit Assignment" (Args)

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
