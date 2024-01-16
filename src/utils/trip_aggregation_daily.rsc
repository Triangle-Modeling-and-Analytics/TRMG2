Macro "Open Daily Matrix Creation Tool Dbox" (Args)
	RunDbox("Daily Matrix Creation Tool", Args)
endmacro

dBox "Daily Matrix Creation Tool" (Args) center, center, 40, 8 Title: "Daily Trip Matrix Creation Tool" Help: "test" toolbox

    close do
        return()
    enditem

    Button 6, 4 Prompt: "Run" do
        RunMacro("Create matrix", Args)
        ShowMessage("Daily trip matrices have been created successfully.")
	return(1)
    enditem
    Button 20, same Prompt: "Quit" do
        Return()
    enditem
    Button 28, same Prompt: "Help" do
        ShowMessage(
         "This tool is used to combine time of day matrices into daily. " +
         "It combine trip matrices for three markets: transit, auto," +
         "and university.\n" +
         "Note: you need to have a complete run to run this tool."
     )
    enditem
enddbox

Macro "Create matrix" (Args)
    scen_dir = Args.[Scenario Folder]
    reporting_dir = scen_dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\Daily_Trip_Matrices"
    RunMacro("Create Directory", output_dir)
    
    //set input path
    periods = Args.periods
    university_dir = scen_dir + "\\output\\university"
    auto_dir = scen_dir + "\\output\\assignment\\roadway"
    transit_dir = scen_dir + "\\output\\assignment\\transit"
    dirs = {auto_dir, transit_dir, university_dir}

    //Create daily matrix
    for dir in dirs do
        //Get market name
        pos = PositionTo(, dir, "\\")
        market = right(dir, len(dir) - pos)
        
        //Create output matrix  
        out_file_daily = output_dir + "\\" + market + "_daily.mtx"
        examples = RunMacro("Catalog Files", {dir: dir, ext: "mtx"}) 
        CopyFile(examples[1], out_file_daily)
        daily_mtx = CreateObject("Matrix", out_file_daily)
        core_names = daily_mtx.GetCoreNames()

        for core_name in core_names do
            daily_mtx.(core_name) := 0 //reset everything to 0
        end 
        
        
        for period in periods do        
            if market = "university" then
                mtx_file = dir + "\\" + market + "_trips_" + period + ".mtx"
            else if market = "roadway" then
                mtx_file = dir + "\\od_veh_trips_" + period + ".mtx"
            else
                mtx_file = dir + "\\" + market + "_" + period + ".mtx"

            for core_name in core_names do
                mtx = CreateObject("Matrix", mtx_file)
                daily_mtx.(core_name) := nz(daily_mtx.(core_name)) + nz(mtx.(core_name))
            end
        end
    end

endmacro