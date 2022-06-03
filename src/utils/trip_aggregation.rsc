Macro "Open Trip Aggregation Tool Dbox" (Args)
	RunDbox("Trip Aggregation Tool", Args)
endmacro

dBox "Trip Aggregation Tool" (Args) center, center, 40, 8 Title: "Trip Matrix Aggregation Tool" Help: "test" toolbox

    close do
        return()
    enditem

    Button 6, 4 Prompt: "Aggregate" do
        RunMacro("Aggregate matrix", Args)
        ShowMessage("Trips have been aggregated successfully.")
	return(1)
    enditem
    Button 20, same Prompt: "Quit" do
        Return()
    enditem
    Button 28, same Prompt: "Help" do
        ShowMessage(
        "This tool is used to combine disaggregate trip matrices into a few trip purposes. " +
         "It generates trip matrix for five purposes : Journey to Work, HB_School, HB_Other, " +
         "HB_Univ, and NHB. " +
         "Note: you need to have a complete run.\n\n"
     )
    enditem
enddbox

Macro "Aggregate matrix" (Args)
    scen_dir = Args.[Scenario Folder]
    reporting_dir = scen_dir + "\\output\\_summaries\\_reportingtool"
    output_dir = reporting_dir + "\\Trip_aggregation"
    RunMacro("Create Directory", output_dir)
    
    //set path
    periods = Args.periods
    resident_dir = scen_dir + "\\output\\resident\\trip_matrices"
    univ_dir = scen_dir + "\\output\\university"
    nhb_dir = scen_dir + "\\output\\resident\\nhb\\dc\\trip_matrices"

    //set core names to combine
    res_corenames = {"sov", "hov2", "hov3", "school bus", "all_transit"}
    purposes = {"HBW", "HBSch", "HBO", "HBU", "NHB"}
    //univ_cores = {"auto", "walk", "bike", "w_lb", "pnr_lb"} all cores in univ mtx
    //nhb-cores = {"sov", "hov2", "hov3", "Total"} all cores in nhb mtx

    for period in periods do

        //Create output matrix
        out_file = output_dir + "/pa_trip_matrix_"+ period + ".mtx"
        res_trip_files = RunMacro("Catalog Files", {dir: resident_dir, ext: "mtx"}) 
        CopyFile(res_trip_files[1], out_file)
        mtx = CreateObject("Matrix", out_file)
        core_names = mtx.GetCoreNames()
        mtx.AddCores({"Total"})
        mtx.DropCores(core_names)
        mtx.AddCores(purposes)
        cores = mtx.GetCores()
        
        //resident trip        
        for trip_file in res_trip_files do
            {, , name, } = SplitPath(trip_file)
            if !Position(name, period) then continue //if mtx is not for this TOD, skip
            trip_mtx = CreateObject("Matrix", trip_file)
            trip_cores = trip_mtx.GetCores()

            if Position(name, "_W_") then do //if work
                for res_corename in res_corenames do
                    cores.("HBW") := nz(cores.("HBW")) + nz(trip_cores.(res_corename))
                end
            end else if Position(name, "_K12_") then do //if school
                for res_corename in res_corenames do
                    cores.("HBSch") := nz(cores.("HBSch")) + nz(trip_cores.(res_corename))
                end
            end else do // if other
                for res_corename in res_corenames do
                    cores.("HBO") := nz(cores.("HBO")) + nz(trip_cores.(res_corename))
                end
            end
        end

        //univ trip
        univ_trip_file = univ_dir + "/university_trips_" + period + ".mtx"
        trip_mtx = CreateObject("Matrix", univ_trip_file)
        trip_corenames = trip_mtx.GetCoreNames()
        trip_cores = trip_mtx.GetCores()
        for trip_corename in trip_corenames do
            cores.("HBU") := nz(cores.("HBU")) + nz(trip_cores.(trip_corename))
        end

        //uhb trip
        nhb_trip_files = RunMacro("Catalog Files", {dir: nhb_dir, ext: "mtx"})
        for trip_file in nhb_trip_files do
            {, , name, } = SplitPath(trip_file)
            if !Position(name, period) then continue //if mtx is not for this TOD, skip
            trip_mtx = CreateObject("Matrix", trip_file)
            trip_corenames = trip_mtx.GetCoreNames()
            trip_cores = trip_mtx.GetCores()
            for trip_corename in trip_corenames do
                cores.("NHB") := nz(cores.("NHB")) + nz(trip_cores.(trip_corename))
            end
        end

        //Calculate total
        for p in purposes do
            cores.("Total") := nz(cores.("Total")) + nz(cores.(p))
        end

        mtx = null
        trip_mtx = null
    end

endmacro