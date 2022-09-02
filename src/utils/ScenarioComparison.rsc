/*
Simple macro needed by the flowchart to open the dbox
*/

Macro "Open Scenario Comp Tool"
    RunDbox("scen_comp_tool")
endmacro

/*
A tool for looking at changes between two link layers.
*/

dBox "scen_comp_tool" center, center, 40, 10 Title: "Scenario Comparison Tool" toolbox

    init do
        static ref_scen, new_scen, sub_poly
    enditem

    close do
        return()
    enditem

    Text 15, 2, 15 Framed Prompt: "Reference Scenario:" Variable: ref_scen
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip1
        ref_scen = ChooseDirectory("Choose reference scenario", )
        skip1:
        on error default
    enditem

    Text 15, after, 15 Framed Prompt: "New Scenario:" Variable: new_scen
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip2
        new_scen = ChooseDirectory("Choose new scenario", )
        skip2:
        on error default
    enditem

    Text 15, after, 15 Framed Prompt: "Subarea Polygon:" Variable: sub_poly
    Button after, same, 5, 1 Prompt: "..." do
        on error, escape goto skip3
        sub_poly = ChooseFile({{"polygon layer", "*.dbd"}}, "Choose a polygon layer", )
        skip3:
        on error default
    enditem

    Button 2, 8 Prompt: "Compare Scenarios" do
        RunMacro("Compare Scenarios", {
            ref_scen: ref_scen,
            new_scen: new_scen,
            sub_poly: sub_poly
        })
        ShowMessage("Scenario comparison complete.")
    enditem
    Button 20, same Prompt: "Quit" do
        Return()
    enditem
    Button 28, same Prompt: "Help" do
        ShowMessage(
            "placeholder"
        )
    enditem
enddbox

Macro "Compare Scenarios" (MacroOpts)

    RunMacro("Compare Summary Tables", MacroOpts)
    RunMacro("Compare Zonal Data", MacroOpts)
endmacro

Macro "Compare Summary Tables" (MacroOpts)

    ref_scen = MacroOpts.ref_scen
    new_scen = MacroOpts.new_scen
    sub_poly = MacroOpts.sub_poly

    // Manually specify which tables to compare here with relative
    // paths. Each table has the file path, id columns, and diff columns
    // specified.
    comp_dir = new_scen + "/comparison_outputs"
    RunMacro("Create Directory", comp_dir)
    tables_to_compare = {
        {"/output/_summaries/resident_hb/hb_trip_mode_shares.csv", {"trip_type", "mode"}, {"Sum", "total", "pct"}},
        {"/output/sedata/scenario_se.bin", {"TAZ"}, {"HH", "HH_POP", "Median_Inc", "Industry", "Office", "Service_RateLow", "Service_RateHigh", "Retail"}},
        {"/output/networks/scenario_links.bin", {"ID"}, {"Total_Flow_Daily", "Total_VMT_Daily", "Total_VHT_Daily", "Total_Delay_Daily"}}
    }
    for i = 1 to tables_to_compare.length do
        table = tables_to_compare[i][1]
        id_cols = tables_to_compare[i][2]
        diff_cols = tables_to_compare[i][3]

        comp_file = comp_dir + table
        {drive, path, , } = SplitPath(comp_file)
        RunMacro("Create Directory", drive + path)
        
        RunMacro("Diff Tables", {
            Table1: ref_scen + table,
            Table2: new_scen + table,
            OutputFile: comp_file,
            IDColumns: id_cols,
            ColumnsToDiff: diff_cols
        })
    end
endmacro

/*
Compares the same table between two scenarios. Can be used for summary CSVs,
se bin table, etc.
*/

Macro "Diff Tables" (MacroOpts)
    
    table1 = MacroOpts.Table1
    table2 = MacroOpts.Table2
    id_cols = MacroOpts.IDColumns
    cols_to_diff = MacroOpts.ColumnsToDiff
    out_file = MacroOpts.OutputFile

    if out_file = null then out_file = Substitute(table2, ".", "_diff.", )
    if cols_to_diff = null then do
        temp = CreateObject("Table", table2)
        field_names = temp.GetFieldNames()
        for id_col in id_cols do
            pos = field_names.position(id_col)
            field_names = ExcludeArrayElements(field_names, pos, 1)
        end
    end

    // Create tables and rename/add fields
    tbl1 = CreateObject("Table", {FileName: table1})
    tbl1 = tbl1.Export({FieldNames: id_cols + cols_to_diff})
    tbl2 = CreateObject("Table", table2)
    tbl2 = tbl2.Export({FieldNames: id_cols + cols_to_diff})
    for col in cols_to_diff do
        tbl1.RenameField({FieldName: col, NewName: col + "_ref"})
        tbl2.RenameField({FieldName: col, NewName: col + "_new"})
        tbl2.AddField(col + "_diff")
    end
    
    // Calculate differences
    tbl3 = tbl1.Join({
        Table: tbl2,
        LeftFields: id_cols,
        RightFields: id_cols
    })
    for col in cols_to_diff do
        tbl3.(col + "_diff") = tbl3.(col + "_new") - tbl3.(col + "_ref")
    end
    tbl3.Export({FileName: out_file})

    // Clean up id name columns
    tbl4 = CreateObject("Table", out_file)
    for col in id_cols do
        tbl4.RenameField({FieldName: "Table_2." + col, NewName: col})
        tbl4.DropFields("Table_3." + col)
    end
endmacro

/*

*/

Macro "Compare Zonal Data" (MacroOpts)
    
    ref_scen = MacroOpts.ref_scen
    new_scen = MacroOpts.new_scen
    sub_poly = MacroOpts.sub_poly

    comp_dir = new_scen + "/comparison_outputs"
    map_dir = comp_dir + "/maps"
    RunMacro("Create Directory", map_dir)

    dbd = new_scen + "/input/tazs/scenario_tazs.dbd"
    map = CreateObject("Map", dbd)
    taz_lyr = map.GetActiveLayer()
    taz_lyr = map.RenameLayer({LayerName: taz_lyr, NewName: "TAZs"})
    taz_tbl =  CreateObject("Table", taz_lyr)
    se_tbl = CreateObject("Table", {FileName: comp_dir + "/output/sedata/scenario_se.bin", View: "se"})
    if sub_poly <> null then do
        se_tbl.AddField("in_subarea")
    end

    join_tbl = taz_tbl.Join({
        Table: se_tbl,
        LeftFields: "ID",
        RightFields: "Table_2.TAZ"
    })

    if sub_poly <> null then do
        // Add the subarea polygon and mark which TAZs are in it.
        {sub_layer} = map.AddLayer({
            FileName: sub_poly,
            LineColor: "Black",
            LineWidth: 2
        })
        map.SelectByVicinity({
            SetName: "subarea",
            SearchLayer: sub_layer
        })
        join_tbl.ChangeSet("subarea")
        join_tbl.in_subarea = 1
        map.DropSet("subarea")
        map.RenameLayer({
            LayerName: sub_layer,
            NewName: "Sub Area"
        })
    end

    jv = join_tbl.GetView()
    fields_to_map = {
        "HH", "HH_POP", "Industry", "Office", "Service_RateLow", 
        "Service_RateHigh", "Retail"
    }
    for field in fields_to_map do
        map.ColorTheme({
            ThemeName: field + " Difference",
            FieldName: jv + "." + field + "_diff",
            NumClasses: 8,
            Method: "Equal Steps",
            BreakAt: 0,
            Colors: {
                StartColor: "blue",
                MidColor: "white",
                EndColor: "red"
            }
        })
        map.CreateLegend()
        map.Save(map_dir + "/" + field + " Differences.map")
    end
endmacro