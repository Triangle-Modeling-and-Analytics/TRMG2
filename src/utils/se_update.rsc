/*
This tool makes it easier to update se data while maintaining county control
totals. An original se data file is used to establish county control totals.
Then a new/updated se file is used to determine which zones were manually
changed. All other zones within the county are adjusted to preserve the original
total.

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
          the se data table.
          
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

    // Calculate control totals
    taz = CreateObject("Table", taz)
    orig = CreateObject("Table", orig_se)
    join = orig.Join({
        Table: taz,
        LeftFields: "TAZ",
        RightFields: "ID"
    })
    totals = join.Aggregate({
        GroupBy: "County",
        FieldStats: {HH: {"sum"}}
    })
    join = null
    
    // Identify modified zones and calc diff by zone
    new = CreateObject("Table", new_se)
    new.AddField("modified")
    new.AddField("diff")
    new.AddField("unmod_cnt_total")
    join = orig.Join({
        Table: new,
        LeftFields: "TAZ",
        RightFields: "TAZ"
    })
    new_vw = new.GetView()
    orig_vw = orig.GetView()
    v_orig_hh = join.(orig_vw + ".HH")
    v_new_hh = join.(new_vw + ".HH")
    v_mod = if v_new_hh <> v_orig_hh then 1 else 0
    v_diff = v_new_hh - v_orig_hh
    join.modified = v_mod
    join.diff = v_diff
    
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
        FieldStats: {HH: {"sum"}}
    })
    join2 = join.Join({
        Table: agg,
        LeftFields: "County",
        RightFields: "County"
    })
    join2.unmod_cnt_total = join2.sum_HH
    join2 = null
    join = null
    new.AddField("pct")
    new.pct = if new.modified <> 1 then new.HH / new.unmod_cnt_total else 0
    
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
    join2.HH = join2.HH - join2.sum_diff * join2.pct    
endmacro