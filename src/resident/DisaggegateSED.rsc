/*
Macro that creates one dimensional marginls for HH by Size, HH by income and HH by workers
Uses curves fit from the ACS data to split HH in each TAZ into subcategories
Creates output file defined by 'Args.SEDMarginals'
*/
Macro "DisaggregateSED"(Args)
    on escape, error, notfound do
        ErrorMsg = GetLastError()
        ret_value = 0
        goto quit
    end

    // Open SED Data and check table for missing fields
    obj = CreateObject("AddTables", {TableName: Args.SEData})
    vwSED = obj.TableView
    flds = {"TAZ", "PUMA5", "Type", "HH", "HH_Pop", "Median_Inc", "Pct_Worker"}
    ExportView(vwSED + "|", "FFB", Args.SEDMarginals, flds,)
    obj = null

    obj = CreateObject("AddTables", {TableName: Args.SEDMarginals})
    vw = obj.TableView

    // Run models to disaggregate curves
    // 1. ==== Size
    opt = {View: vw, Curve: Args.SizeCurves, KeyExpression: "HH_Pop/HH", LookupField: "avg_size"}
    RunMacro("Disaggregate SE HH Data", opt)

    // 2. ==== Income
    opt = {View: vw, Curve: Args.IncomeCurves, KeyExpression: "Median_Inc/" + String(Args.RegionalMedianIncome), LookupField: "inc_ratio"}
    RunMacro("Disaggregate SE HH Data", opt)

    // 3. ==== Workers
    opt = {View: vw, Curve: Args.WorkerCurves, KeyExpression: "((Pct_Worker/100)*HH_Pop)/HH", LookupField: "avg_workers"}
    RunMacro("Disaggregate SE HH Data", opt)

    obj = null
    ret_value = 1
   quit:
    on error, notfound, escape default
    if !ret_value then do
        if ErrorMsg <> null then
            AppendToLogFile(0, ErrorMsg)
    end
    Return(ret_value)
endMacro


/*
Macro that disaggregates HH field in TAZ into categories based on input curves
Options to the macro are:
View: The SED view that contains TAZ, HH and other pertinent info
Curve: The csv file that contains the disaggregate curves. 
        E.g. 'size_curves.csv', that contains 
            - One field for the average HH size and
            - Four fields that contain fraction of HH by Size (1,2,3,4) corresponding to each value of average HH size
LookupField: The key field in the curve csv file. e.g. 'avg_size' in the 'size_curves.csv' table
KeyExpression: The expression in the SED view that is used to match the lookup field in the curve file (e.g 'HH_POP/HH')

Macro adds fields to the SED view and populates them.
It adds as many fields as indicated by the input curve csv file
In the above example, fields added will be 'HH_Size1', 'HH_Size2', 'HH_Size3', 'HH_Size4'
For records in SED data that fall outside the bounds in the curve.csv file, the appropriate limiting values from the curve table are used.
*/
Macro "Disaggregate SE HH Data"(opt)
    // Open curve and get file characteristics
    objC = CreateObject("AddTables", {TableName: opt.Curve})
    vwC = objC.TableView
    lookupFld = Lower(opt.LookupField)
    {flds, specs} = GetFields(vwC,)
    fldsL = flds.Map(do (f) Return(Lower(f)) end)

    // Add output fields to view
    vw = opt.View
    modify = CreateObject("CC.ModifyTableOperation", vw)
    categoryFlds = null
    for fld in fldsL do
        if fld <> lookupFld then do // No need to add lookup field
            categoryFlds = categoryFlds + {fld}
            modify.AddField("HH_" + fld, "Long", 12,,) // e.g. Add Field 'HH_Size1'
        end
    end
    modify.Apply()

    // Get the range of values in lookupFld
    vLookup = GetDataVector(vwC + "|", lookupFld,)
    m1 = VectorStatistic(vLookup, "Max",)
    maxVal = r2i(Round(m1*100, 2))
    m2 = VectorStatistic(vLookup, "Min",)
    minVal = r2i(Round(m2*100, 2))
    exprStr = "r2i(Round(" + lookupFld + "*100,2))"             // e.g. r2i(Round(avg_size*100,0))
    exprL = CreateExpression(vwC, "Lookup", exprStr,)

    // Create expression on SED Data
    // If computed value is beyond the range, set it to the appropriate limit (minVal or maxVal)
    vw = opt.View
    expr = "r2i(Round(" + opt.KeyExpression + "*100,2))"        // e.g. r2i(Round(HH_POP/HH*100,0))
    exprStr = "if " + expr + " = null then null " +
              "else if " + expr + " < " + String(minVal) + " then " + String(minVal) + " " +
              "else if " + expr + " > " + String(maxVal) + " then " + String(maxVal) + " " +
              "else " + expr
    exprFinal = CreateExpression(vw, "Key", exprStr,) 

    // Join SED Data to Lookup and compute values
    vecsOut = null
    vwJ = JoinViews("SEDLookup", GetFieldFullSpec(vw, exprFinal), GetFieldFullSpec(vwC, exprL),)
    vecs = GetDataVectors(vwJ + "|", {"HH"} + categoryFlds, {OptArray: 1})
    vTotal = Vector(vecs.HH.Length, "Long", {{"Constant", 0}})
    for i = 2 to categoryFlds.length do // Do not compute for first category yet, hence the 2.
        fld = categoryFlds[i]
        vVal = r2i(vecs.HH * vecs.(fld))    // Intentional truncation of decimal part
        vecsOut.("HH_" + fld) = nz(vVal)
        vTotal = vTotal + nz(vVal)      
    end
    finalFld = categoryFlds[1]
    vecsOut.("HH_" + finalFld) = nz(vecs.HH) - vTotal // Done to maintain clean marginals that exactly sum up to HH
    SetDataVectors(vwJ + "|", vecsOut,)
    CloseView(vwJ)
    objC = null

    DestroyExpression(GetFieldFullSpec(vw, exprFinal))
endMacro
