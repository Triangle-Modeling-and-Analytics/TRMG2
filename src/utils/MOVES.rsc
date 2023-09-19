Macro "Open Prepare MOVES Input Dbox" (Args)
	RunDbox("Prepare MOVES Input", Args)
endmacro

dBox "Prepare MOVES Input" (Args) location: center, center, 46, 7
  Title: "MOVES Input Preparation" toolbox NoKeyBoard

  // What happens when the "x" is clicked
  close do
    return()
  enditem

  init do

    static region_list, year_list
	
    taz_dbd = Args.TAZs
    taz_bin = Substitute(taz_dbd, ".dbd", ".bin",)
    taz_vw = OpenTable("taz","FFB", {taz_bin})
    county = GetDataVector(taz_vw + "|", "County", )
    //mpo = GetDataVector(taz_vw + "|", "MPO", )
    mpo_list = {"DCHC", "CAMPO"}
    county_list = SortVector(county, {Unique: "true"})
    //mpo_list = SortVector(mpo, {Unique: "true"})
    //region_list = {"All_region"} + V2A(county_list) + V2A(mpo_list)
    region_list = {"All_region"} + V2A(county_list) + mpo_list
    year_list = {"2020", "2025", "2030", "2035", "2040", "2045", "2050"}
	  
    EnableItem("Select region")
    EnableItem("Select year")
	  
   enditem
  
  // region_list Button
  Popdown Menu "Select region" 31,1,10,5 Prompt: "Choose region to produce input" 
    List: region_list Variable: region_index do
    region = region_list[region_index]
  enditem

  // year_list Button
  Popdown Menu "Select year" 22,3,10,5 Prompt: "Choose scenario year" 
    List: year_list Variable: year_index do
    year = year_list[year_index]
  enditem

  // Quit Button
  button 4, 5, 10 Prompt:"Quit" do
    Return(1)
  enditem

  // Help Button
  button 32, 5, 8 Prompt:"Help" do
    ShowMessage(
        "This tool is to prepare inputs for MOVES air quality analysis. Please select the corresponding year from the drop down list based on your selected scenario."
     )
  enditem

  // Run Button
  button 19, 5, 8 Prompt:"Run" do 

    if !RunMacro("MOVES", Args, region, year) then Throw("Something went wrong")
 
    ShowMessage("Reports have been created successfully.")
	return(1)
	
    exit:	
    showmessage("Something is wrong")	
    return(0)
  Enditem
Enddbox


//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
//                        Macro "MOVES"
//@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Macro "MOVES" (Args, region, year)

  //Set path
  hwy_dbd = Args.Links
  popsyn_dir = Args.[Output Folder] + "/resident/population_synthesis"
  MOVES_dir = Args.[Base Folder] + "/other/_reportingtool/MOVES"
  summary_dir = Args.[Output Folder] + "/_summaries/MOVES/" + region
  assn_dir = Args.[Output Folder] + "/assignment/roadway"
  periods = Args.periods
  taz_dbd = Args.TAZs
  RunMacro("Create Directory", MOVES_dir)
  RunMacro("Create Directory", summary_dir)

  // Read MOVES templates
  roadtype_file = MOVES_dir + "/fixed_template/Roadtype_template.csv"
  sourcetype_file = MOVES_dir + "/fixed_template/Sourcetype_template.csv"
  hour_file = MOVES_dir + "/fixed_template/HourVMT_template.csv"
  speed_file = MOVES_dir + "/fixed_template/speed_template.csv"
  
  // Read factor files
  sourcetypeparam_file = MOVES_dir + "/SourceType_param.csv"
  monthparam_file = MOVES_dir + "/Month_param.csv"
  weekendparam_file = MOVES_dir + "/Weekend_param.csv"
  todparam_file = MOVES_dir + "/TOD_param.csv"
  
  // Determine region type
  region_type = if region = "All_region" then  "All_region"
    else if region = "DCHC" or region = "CAMPO" then "MPO"
    else "County"

  // Read highway layer
  objLyrs = CreateObject("AddDBLayers", {FileName: hwy_dbd})
  {nlayer, llyr} = objLyrs.Layers
  SetLayer(llyr)
  SelectByQuery("sel", "several", "Select * where D = 1 and HCMType <> 'CC'")
  if region_type = "County" then SelectByQuery("sel", "subset", "Select * where County = '" + region + "'")
  if region_type = "MPO" then SelectByQuery("sel", "subset", "Select * where MPO = '" + region + "'")

  //1. Link table
  df = CreateObject("df")
  fields_to_sum = {"Total_Flow_Daily", "Total_VMT_Daily", "Total_VHT_Daily",
                    "Tot_Flow_AM", "Tot_VMT_AM", "Tot_VHT_AM", 
                    "Tot_Flow_MD", "Tot_VMT_MD", "Tot_VHT_MD", 
                    "Tot_Flow_PM", "Tot_VMT_PM", "Tot_VHT_PM", 
                    "Tot_Flow_NT", "Tot_VMT_NT", "Tot_VHT_NT"}
  df.read_view({
    view: llyr,
    set: "sel",
    fields: {"ID", "Length", "HCMType", "AreaType", "County"} + fields_to_sum
  })
  v_roadtype = df.tbl.HCMType
  v_roadtype = if v_roadtype = "Freeway" then "Restricted Access" else "Unrestricted Access"
  v_at = if df.tbl.AreaType = "Rural" then "Rural" else "Urban"
  v_roadtype = v_at + " " + v_roadtype
  v_movestype = if v_roadtype = "Rural Restricted Access" then 2 else if v_roadtype = "Rural Unrestricted Access"  then 3 
                else if v_roadtype = "Urban Restricted Access" then 4 else 5  
  df.mutate("roadTypeID", v_movestype)
  df.write_csv(summary_dir + "/link_table.csv") // save link table as an output

  // Aggregate by moves type for easy calculation
  agg = df.copy()
  agg.group_by("roadTypeID") 
  agg.summarize(fields_to_sum, "sum")
  names = agg.colnames()
  for name in names do
      if Left(name, 4) = "sum_" then do
          new_name = Substitute(name, "sum_", "", 1)
          agg.rename(name, new_name)
      end
  end
  agg.write_csv(summary_dir + "/agg_link_table.csv")
  /*
  // TOD Assignment tables
  for period in periods do 
    assn_file = assn_dir + "/roadway_assignment_" + period + ".bin"
    assn_vw = OpenTable("asn", "FFB", {assn_file})
    df2 = CreateObject("df")
    df2.read_view({
      view: assn_vw,
      fields: {"ID1", "AB_Flow", "BA_Flow", "Tot_Flow", "AB_Speed", "BA_Speed", "AB_VMT", "BA_VMT", "Tot_VMT"}
    })
    df3 = df.copy()
    df3.left_join(df2, "ID", "ID1")
    names = df3.colnames()
    for name in names do
        if Position(name, "_") then do
            new_name = Substitute(name, "_", "_" + period + "_", 1)
            df3.rename(name, new_name)
        end
    end
    df3.write_csv(summary_dir + "/" + period + "_assignment_table.csv")
    CloseView(assn_vw)
  end
  */
 
  //2. Vehicle population
  if region_type = "All_region" then do
    hh_vw = OpenTable("hh", "FFB", {popsyn_dir + "/Synthesized_HHs.bin"})
    v = GetDataVector(hh_vw + "|", "Autos", )
    veh_total = VectorStatistic(v, "Sum", )
    CloseView(hh_vw)
    out_file = summary_dir + "/total_vehicles.csv"
    f = OpenFile(out_file, "w")
    WriteLine(f, String(veh_total))
    CloseFile(f)
  end else do
    taz_bin = Substitute(taz_dbd, ".dbd", ".bin",)
    taz = CreateObject("df", taz_bin)
    hh = CreateObject("df", popsyn_dir + "/Synthesized_HHs.bin")
    hh.left_join(taz, "ZoneID", "ID")
    hh.group_by("County")
    hh.summarize("Autos", "sum")
    hh.write_csv(summary_dir + "/county_vehicles.csv")
  end


  //3. Road type output
  roadtype = Createobject("df", roadtype_file)
  agg.mutate("roadTypeVMTFraction", agg.tbl.Total_VMT_Daily/agg.tbl.Total_VMT_Daily.sum())
  roadtype.left_join(agg,"roadTypeID", "roadTypeID")
  roadtype.select({"sourcetypeID", "roadTypeID", "roadTypeVMTFraction"})
  roadtype.write_csv(summary_dir + "/roadtype.csv")
  
  //4. Sourcetype output
  sourcetype = Createobject("df", sourcetype_file)
  sourcetypeparam = Createobject("df", sourcetypeparam_file)
  monthparam = Createobject("df", monthparam_file)
  weekendparam = Createobject("df", weekendparam_file)

  sourcetype. mutate("year", s2i(year))
  sourcetype.left_join(sourcetypeparam, {"sourcetypeID", "year"}, {"sourcetypeID", "year"})
  sourcetype.left_join(monthparam, "month")
  sourcetype.left_join(weekendparam, {"year", "day"}, {"year", "day"})
	tot_VMT = agg.tbl.Total_VMT_Daily.sum()
  sourcetype.mutate("VMT", sourcetype.tbl.styFactor * sourcetype.tbl.month_model * sourcetype.tbl.wkFactor * tot_VMT)
  sourcetype.select({"sourcetypeID", "month", "day", "year", "styFactor", "VMT"})
  sourcetype.write_csv(summary_dir + "/sourcetype_vmt.csv")
  
  //5. Hour output
  hour = Createobject("df", hour_file)
  todparam = Createobject("df", todparam_file)
  hour.left_join(todparam, "hour", "hour")
  hour.left_join(agg, "roadTypeID", "roadTypeID")
  hour.mutate("hourlyvmt", if hour.tbl.TOD = "AM" then hour.tbl.Tot_VMT_AM/2 * hour.tbl.hourFac else if hour.tbl.TOD = "MD" then hour.tbl.Tot_VMT_MD/6.5 * hour.tbl.hourFac 
                            else if hour.tbl.TOD = "PM" then hour.tbl.Tot_VMT_PM/2.75 * hour.tbl.hourFac else hour.tbl.Tot_VMT_NT/12.75 * hour.tbl.hourFac)
  hour.group_by({"sourcetypeID", "roadTypeID", "day", "hour"})
  hour.summarize({"hourlyvmt", "Total_VMT_Daily", "hourvmtfraction"}, {"sum", "avg"})
  hour.mutate("hourlypct", if hour.tbl.dayID = 5 then hour.tbl.sum_hourlyVMT/hour.tbl.sum_Total_VMT_Daily else hour.tbl.avg_hourvmtfraction)
  hour.select({"sourcetypeID", "roadTypeID", "day", "hour", "hourlypct"})
  hour.write_csv(summary_dir + "/hourlyvmt.csv")

  //6. Speed output
  df1 = df.copy()
  //Calculate speed bin
  for period in periods do
    // first calculate speed, as DBD file only has AB/BA speed.
    v_vmt = df1.get_col("Tot_VMT_" + period)
    v_vht = df1.get_col("Tot_VHT_" + period)
    v_speed = v_vmt/v_vht
    df1.mutate("speed_" + period, v_speed)
    df1.mutate("speedbin_"+ period, if df1.tbl.("speed_" + period) <72.5 then Ceil((df1.tbl.("speed_" + period) + 2.5)/5) else 16)
  end

  //Calculate VHT fraction
  gather_cols = {"speedbin_AM", "speedbin_MD", "speedbin_PM", "speedbin_NT"} // wide table to long
  df1.gather(gather_cols, "TOD", "bin")
  df1.mutate("TOD", right(df1.tbl.("TOD"), 2))
  df1.mutate("VHT", if df1.tbl.TOD = "AM" then df1.tbl.Tot_VHT_AM else if df1.tbl.TOD = "MD" then df1.tbl.Tot_VHT_MD else if df1.tbl.TOD = "PM" then df1.tbl.Tot_VHT_PM else df1.tbl.Tot_VHT_NT)
  df1.group_by({"TOD", "roadTypeID", "bin"})
  df1.summarize("VHT", "sum")
  df1.rename("sum_VHT", "VHT")
  df1.filter("bin <> null")

  df2 = df1.copy()
  df2.group_by({"TOD", "roadTypeID"})
  df2.summarize("VHT", "sum") //get the sum
  df2.rename('sum_VHT', "total_VHT")

  df1.left_join(df2, {"TOD", "roadTypeID"}, {"TOD", "roadTypeID"})
  df1.mutate("Fraction", if df1.tbl.VHT/df1.tbl.total_VHT>0 then df1.tbl.VHT/df1.tbl.total_VHT else 0) // get fraction

  //Join results to the speed template
  speed = Createobject("df", speed_file)
  speed.rename("avgSpeedFraction", "DefaultFraction")
  speed.left_join(df1, {"TOD", "roadTypeID", "avgSpeedBinID"}, {"TOD", "roadTypeID", "bin"})
  speed.mutate("AvgSpeedFraction", if speed.tbl.dayID <>2 then speed.tbl.Fraction else speed.tbl.DefaultFraction) // weekend fraction should be set to default
  speed.select({"sourceTypeID", "roadTypeID", "hourDayID", "hourID", "dayID", "TOD", "avgSpeedBinID", "AvgSpeedFraction"})
  speed.write_csv(summary_dir + "/speed.csv")

  DeleteFile(summary_dir + "/agg_link_table.csv")
  DeleteFile(summary_dir + "/link_table.csv")
  
  return(1)

endmacro
