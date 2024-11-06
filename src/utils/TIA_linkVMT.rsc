Macro "Open TIA Link VMT Dbox" (Args)
	RunDbox("TIA Link VMT", Args)
endmacro

dBox "TIA Link VMT" (Args) center, center, 60, 10 
    Title: "Link VMT Metric" Help: "test" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static  Scen_Dir, Scenroot_Dir, Scen_Name, full_scen_dir

        Scenroot_Dir = Args.[Scenarios Folder]
        Scen_Dir = Args.[Scenario Folder]
        Scen_Name = Substitute(Scen_Dir, Scenroot_Dir + "\\", "",)

    enditem

    // Selected Scenario
    Text 40, 1, 15 Prompt: "Scenario with development (current scenario):" Variable: Scen_Name

    // Input threshold
    Edit Int 33, after, 5 Prompt: "Minimum # of trips for local market:" Variable: loc_thresh
    Edit Int 37, after, 5 Prompt: "Minimum # of trips for extended market:" Variable: ext_thresh

    Edit Text 18, after, 15 Prompt: "Base Scenario Dir:" Variable: full_scen_dir
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip1
        full_scen_dir = ChooseDirectory("Choose Full Scenario Folder", {"Initial Directory": scen_dir})
        skip1:
        on error default
    enditem

    // Quit Button
    button 5, 8, 10 Prompt:"Quit" do
        Return(1)
    enditem

    // Run Button
    button 18, 8, 20 Prompt:"Generate Results" do 

        if !RunMacro("TIA Link VMT", Args, loc_thresh, ext_thresh, full_scen_dir) then Throw("Something went wrong")
 
        ShowMessage("Reports have been created successfully.")
	return(1)
	
    exit:	
        showmessage("Something is wrong")	
        return(0)
    Enditem

    Button 41, 8, 10 Prompt: "Help" do
        ShowMessage(
        "This tool is used to calculate link VMT metric for TIA projects." +
        " User must interatively identify trip threshold for each market" +
        " before running this tool. The base scenario (w/o development) must" +
        " be completed beforehand. See wiki user guide for more detais."
     )
    enditem
enddbox

Macro "TIA Link VMT" (Args, loc_thresh, ext_thresh, full_scen_dir)
    dir = Args.[Scenario Folder]
    link_dbd = Args.Links
    base_link_bin = full_scen_dir + "\\output\\networks\\scenario_links.BIN"
    taz_dbd = Args.TAZs
    periods = Args.Periods
    reporting_dir = dir + "\\output\\_summaries"
    output_dir = reporting_dir + "\\VMT_TIA"
    
    // 1. Load assignment network with select link volumne and Caculate daily query flow
    {map, {node_lyr, link_lyr}} = RunMacro("Create Map", {file: link_dbd})
    {taz_lyr} = GetDBLayers(taz_dbd)
    taz_lyr = AddLayer(map, taz_lyr, taz_dbd, taz_lyr)

    link_fields =  {{"Total_Flow_Query1", "Real", 10, 2,,,, "Select link volume"}}
    RunMacro("Add Fields", {view: link_lyr, a_fields: link_fields})
    taz_fields =  {{"is_local_mkt", "Integer", 10, ,,,, "if TAZ is in local market for TIA analysis."},
                    {"is_extended_mkt", "Integer", 10, ,,,, "if TAZ is in extended market for TIA analysis."}}
    RunMacro("Add Fields", {view: taz_lyr, a_fields: taz_fields})

    a_dirs = {"AB", "BA"}
    v_queryflow = null
    for a_dir in a_dirs do
        for period in periods do
            input_field = a_dir + "_Flow_Query1_" + period
            v_flow = GetDataVector(link_lyr + "|", input_field, )
            v_queryflow = nz(v_queryflow) + nz(v_flow)
        end
    end
    SetDataVector(link_lyr + "|", "Total_Flow_Query1", v_queryflow, )

    // 2. Defines market
    SetSelectInclusion("Intersecting")
    markets = {"local", "extended", "regional"}
    for market in markets do
        SetLayer(link_lyr)
        thresh = if market = "local" then loc_thresh
            else if market = "extended" then ext_thresh
            else null

        if thresh <> null then do //for local and extended, use select by location to determine market
            query = "Select * where HCMType <> 'TransitOnly' and HCMType <> null and HCMType <> 'CC' and Total_Flow_Query1 >=" + i2s(thresh)
            n1 = SelectByQuery(market, "several", query)
            
            SetLayer(taz_lyr)
            n2 = SelectByVicinity(market + "_taz", "several", link_lyr + "|" + market, 0,)
            v = Vector(n2, "Short", {{"Constant", 1}})
            SetDataVector(taz_lyr + "|" + market + "_taz", "is_" + market + "_mkt", v, )

            SetLayer(link_lyr)
            n3 = SelectByVicinity(market + "_links", "several", taz_lyr + "|" + market + "_taz", 0,)
            n4 = SelectByQuery(market + "_links", "subset", "Select * where HCMType <> 'TransitOnly' and HCMType <> null and HCMType <> 'CC'")
        end
        else //for regional, no need to create market
            n = SelectByQuery(market + "_links", "several", "Select * where HCMType <> 'TransitOnly' and HCMType <> null and HCMType <> 'CC'")
    end
    
    // 3. Create output
    summary_file = output_dir + "/Link_vmt.csv"
    f = OpenFile(summary_file, "w")
    WriteLine(f, "Market, Base_Total_VMT_Daily, New_Total_VMT_Daily")  

    // 4. Join base network and write output
    base_link_vw = OpenTable("base_link", "FFB", {base_link_bin, })
    SetMap(map)
	SetLayer(link_lyr)
    jv = JoinViews("jv", link_lyr + ".ID", base_link_vw + ".ID", )
	SetView(jv)

    for market in markets do
        v_vmt = GetDataVector(jv + "|" + market + "_links", link_lyr + ".Total_VMT_Daily", )
        vmt = VectorStatistic(nz(v_vmt), "sum",)

        v_base_vmt = GetDataVector(jv + "|" + market + "_links", base_link_vw + ".Total_VMT_Daily", )
        base_vmt = VectorStatistic(nz(v_base_vmt), "sum",)

        WriteLine(f, market + "," + r2s(base_vmt) + "," + r2s(vmt))    
    end
    
    CloseFile(f)
    CloseView(jv)
    CloseView(base_link_vw)
    CloseMap(map)
    Return(1)    
endmacro

