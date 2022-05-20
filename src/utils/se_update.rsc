/*
This tool makes it easier to update se data while maintaining county control
totals. An original se data file is used to establish county control totals.
Then a new/updated se file is used to determine which zones were manually
changed. All other zones within the county are adjusted to preserve the original
total.
*/

Macro "Open SEUpdate Dbox" (Args)
	RunDbox("SEUpdate", Args)
endmacro
dBox "SEUpdate" (Args) location: x, y, , 15
    Title: "SE Data Update Tool" toolbox NoKeyBoard

    close do
        return()
    enditem

    init do
        static x, y, initial_dir, taz_dir, orig_se, new_se, taz_dbd
        if x = null then x = -3
        if taz_dbd = null then taz_dbd = Args.[Master TAZs]
    enditem

    // Original SE
    text 1, 0 variable: "Original SE"
    text same, after, 40 variable: orig_se framed
    button after, same, 6 Prompt: "..."  default do
        on escape goto nodir
        orig_se = ChooseFile(
            {{"Original SE Data", "*.bin"}},
            "Select original se data file",
            {"Initial Directory": initial_dir}
        )
        {drive, path, name, ext} = SplitPath(orig_se)
        initial_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage("The original SE data. Used to calculate county control totals.")
    enditem

    // New SE Data
    text 1, after variable: "New SE"
    text same, after, 40 variable: new_se framed
    button after, same, 6 Prompt: "..."  do
        on escape goto nodir
        new_se = ChooseFile(
            {{"New SE Data", "*.bin"}},
            "Select new link layer",
            {"Initial Directory": initial_dir}
        )
        {drive, path, name, ext} = SplitPath(new_se)
        initial_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage("The new se data where some zones have been modified.")
    enditem

    // TAZ Layer
    text 1, after variable: "TAZ Layer"
    text same, after, 40 variable: taz_dbd framed
    button after, same, 6 Prompt: "..."  do
        on escape goto nodir
        taz_dir = Args.[Model Folder] + "\\master\\tazs"
        taz_dbd = ChooseFile(
            {{"TAZ Layer", "*.dbd"}},
            "Select taz layer",
            {{"Initial Directory", taz_dir}}
        )
        {drive, path, , } = SplitPath(taz_dbd)
        taz_dir = drive + path
        nodir:
        on error, notfound, escape default
    enditem
    button after, same, 3 Prompt: "?"  do
        ShowMessage(
            "The taz layer is used to lookup the county of each zone."
        )
    enditem

    // Quit Button
    button 1, 13, 10 Prompt:"Quit" do
        Return(1)
    enditem

    // Help Button
    button 22, same, 10 Prompt:"Help" do
        ShowMessage(
            "For some applications, a modeler may want to increase the " + 
            "employment or housing in several zones while maintaining the " +
            "county-level totals.\n\n" +
            "Modify the zones of interest in the new se data file. The original " +
            "file is used to calculate county-level control totals, and the " +
            "unchanged zones in the new se data will be modified so that the " +
            "county totals remain unchanged.\n\n" +
            "Supported Fields: HH, HH_POP, and employment by type fields"
        )
    enditem

    // Update Button
    button 42, same, 10 Prompt:"Update" do
        if orig_se = null then Throw("Choose the original link layer")
        if new_se = null then Throw("Choose the new link layer")
        if taz_dbd = null then Throw("Choose the polygon layer that defines the region to be updated.")
        
        RunMacro("SEUpdate", {
            OrigSE: orig_se,
            NewSE: new_se,
            TAZ: taz_dbd
        })
        ShowMessage("SE Data update complete.")
    enditem

enddbox

/*
Inputs
    * OrigSE
        * String
        * File path to original se data. This se data is used to calculate
          county-level control totals.
    * NewSE
        * String
        * The updated se data. This is used to determine which zones were
          manually adjusted.
    * TAZ
        * String
        * The TAZ file. This is needed because county info is not stored on
          the se data table. Either the dbd or bin file can be provided.
          
*/

Macro "test"
    RunMacro("SEUpdate", {
        OrigSE: "C:\\projects\\TRM\\trm_project\\repo_trmg2\\master\\sedata\\se_2020.bin",
        NewSE: "C:\\projects\\TRM\\trm_project\\repo_trmg2\\master\\sedata\\se_2020_new.bin",
        TAZ: "C:\\projects\\TRM\\trm_project\\repo_trmg2\\master\\tazs\\master_tazs.BIN"
    })
endmacro

Macro "SEUpdate" (MacroOpts)

    orig_se = MacroOpts.OrigSE
    new_se = MacroOpts.NewSE
    taz = MacroOpts.TAZ

    if TypeOf(orig_se) = "null" then Throw("SEUpdate: 'OrigSE' is null.")
    if TypeOf(orig_se) <> "string" then Throw("SEUpdate: 'OrigSE' must be a string.")
    if GetFileInfo(orig_se) = null then Throw("SEUpdate: 'OrigSE' file does not exist.")
    if TypeOf(new_se) = "null" then Throw("SEUpdate: 'NewSE' is null.")
    if TypeOf(new_se) <> "string" then Throw("SEUpdate: 'NewSE' must be a string.")
    if GetFileInfo(new_se) = null then Throw("SEUpdate: 'NewSE' file does not exist.")
    if TypeOf(taz) = "null" then Throw("SEUpdate: 'TAZ' is null.")
    if TypeOf(taz) <> "string" then Throw("SEUpdate: 'TAZ' must be a string.")
    if GetFileInfo(taz) = null then Throw("SEUpdate: 'TAZ' file does not exist.")
    {drive, path, name, ext} = SplitPath(taz)
    if ext = ".dbd" then taz = Substitute(taz, ext, ".bin", )

    fields_to_update = {
        "HH", "HH_POP", "Industry", "Office", "Service_RateLow", 
        "Service_RateHigh", "Retail"
    }

    // Calculate control totals
    taz = CreateObject("Table", taz)
    orig = CreateObject("Table", orig_se)
    join = orig.Join({
        Table: taz,
        LeftFields: "TAZ",
        RightFields: "ID"
    })
    for field in fields_to_update do
        field_stats = field_stats + {{field, {"sum"}}}
    end
    totals = join.Aggregate({
        GroupBy: "County",
        FieldStats: field_stats
    })
    join = null

    new = CreateObject("Table", new_se)
    new.AddField("modified")
    new.AddField("diff")
    new.AddField("unmod_cnt_total")
    new.AddField("pct")
    new_vw = new.GetView()
    orig_vw = orig.GetView()
    orig_and_new = orig.Join({
        Table: new,
        LeftFields: "TAZ",
        RightFields: "TAZ"
    })

    for field in fields_to_update do
    
        // Identify modified zones and calc diff by zone
        v_orig = orig_and_new.(orig_vw + "." + field)
        v_new = orig_and_new.(new_vw + "." + field)
        v_mod = if v_new <> v_orig then 1 else 0
        if v_mod.sum() = 0 then continue // skip if nothing modified
        v_diff = v_new - v_orig
        orig_and_new.modified = v_mod
        orig_and_new.diff = v_diff
        
        // Calc diff by county
        join = new.Join({
            Table: taz,
            LeftFields: "TAZ",
            RightFields: "ID"
        })
        county_diff = join.Aggregate({
            GroupBy: "County",
            FieldStats: {diff: {"sum"}}
        })
        
        // For each non-modified zone, determine its % of its county
        join.CreateSet({SetName: "unmodified", Filter: "modified = 0"})
        join.ChangeSet("unmodified")
        agg = join.Aggregate({
            GroupBy: "County",
            FieldStats: {{field, {"sum"}}}
        })
        join2 = join.Join({
            Table: agg,
            LeftFields: "County",
            RightFields: "County"
        })
        join2.unmod_cnt_total = join2.("sum_" + field)
        join2 = null
        join = null
        new.pct = if new.modified <> 1 then new.(field) / new.unmod_cnt_total else 0
        
        // Redistribute county differences
        join = new.Join({
            Table: taz,
            LeftFields: "TAZ",
            RightFields: "ID"
        })
        join2 = join.Join({
            Table: county_diff,
            LeftFields: "County",
            RightFields: "County"
        })
        join2.(field) = join2.(field) - join2.sum_diff * join2.pct
        join2 = null
        join = null
    end
    orig_and_new = null
    new.DropFields({FieldNames: {"diff", "unmod_cnt_total", "pct"}})
endmacro