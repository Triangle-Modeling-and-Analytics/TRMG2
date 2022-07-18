/*

*/

Macro "Disaggregate Curves" (Args)
    RunMacro("DisaggregateSED", Args)
    return(1)
endmacro

Macro "IPU Synthesis" (Args)
    RunMacro("Synthesize Population", Args)
    RunMacro("PopSynth Post Process", Args)
    return(1)
endmacro

Macro "Auto Ownership" (Args)
    RunMacro("Create AO Features", Args)
    RunMacro("Calculate Auto Ownership", Args)
    return(1)
endmacro

/*
Macro that creates one dimensional marginls for HH by Size, HH by income and HH by workers
Uses curves fit from the ACS data to split HH in each TAZ into subcategories
Creates output file defined by 'Args.SEDMarginals'
*/
Macro "DisaggregateSED"(Args)
    // on escape, error, notfound do
    //     ErrorMsg = GetLastError()
    //     ret_value = 0
    //     goto quit
    // end

    // Open SED Data and check table for missing fields
    obj = CreateObject("AddTables", {TableName: Args.SE})
    vwSED = obj.TableView
    flds = {"TAZ", "Type", "HH", "HH_Pop", "Median_Inc", "Pct_Worker", "Pct_Child", "Pct_Senior"}
    expOpts.[Additional Fields] = {{"Kids", "Integer", 12,,,,},
                                   {"AdultsUnder65", "Integer", 12,,,,},
                                   {"Seniors", "Integer", 12,,,,},
                                   {"PUMA5", "Integer", 12,,,,}}
    ExportView(vwSED + "|", "FFB", Args.SEDMarginals, flds, expOpts)
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

    // Fill number of kids, adults and seniors
    vecs = GetDataVectors(vw + '|', {"HH_Pop", "Pct_Child", "Pct_Senior"}, {OptArray: 1})
    vecsSet = null
    vecsSet.Kids = r2i(vecs.HH_Pop * vecs.Pct_Child/100)
    vecsSet.Seniors = r2i(vecs.HH_Pop * vecs.Pct_Senior/100)
    vecsSet.AdultsUnder65 = vecs.HH_Pop - vecsSet.Kids - vecsSet.Seniors
    SetDataVectors(vw + '|', vecsSet,)

    // Fill PUMA5 field using PUMA info from the master TAZ database
    objLyrs = CreateObject("AddDBLayers", {FileName: Args.TAZs})
    {TAZLayer} = objLyrs.Layers
    vwJ = JoinViews("SED_TAZ", GetFieldFullSpec(vw, "TAZ"), GetFieldFullSpec(TAZLayer, "ID"),)
    v = GetDataVector(vwJ + "|", "PUMA",)
    vOut = s2i(Right(v,5))
    SetDataVector(vwJ + "|", "PUMA5", vOut,)
    CloseView(vwJ)
    objLyrs = null

    obj = null
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
In the above example, fields added will be 'HH_siz1', 'HH_siz2', 'HH_siz3', 'HH_siz4'
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
            modify.AddField("HH_" + fld, "Long", 12,,) // e.g. Add Field 'HH_siz1'
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

/*
    * Macro that performs population synthesis using the TransCAD (9.0) built-in procedure. 
        * Marginal Data - Disaggregated SED Marginals (by TAZ)
        * HH Dimensions are:
            * HH By Size - 1, 2, 3 and 4+
            * HH By Workers - 0, 1, 2 and 3+
            * HH By Income Category - 1: [0, 25000); 2: [25000, 75000); 3. [75000, 150000); 4. 150000+
        * For Persons, a match to the total population (HH_POP) by TAZ is attempted via the IPU (Iterational Proportional Update) option using:
            * Age - Three categories. Kids: [0, 17], AdultsUnder65: [18, 64], Seniors: 65+.
*/
Macro "Synthesize Population"(Args)

    // Set up and run the synthesis
    o = CreateObject("PopulationSynthesis")
    o.RandomSeed = 314159
    
    // Define Seed Data. Specify relationship between HH file and TAZ and between HH and Person file
    o.HouseholdFile({FileName: Args.[PUMS HH Seed], /*Filter: "NP <= 10",*/ ID: "HHID", MatchingID: "PUMA", WeightField: "WGTP"})
    o.PersonFile({FileName: Args.[PUMS Person Seed], ID: "PersonID", HHID: "HHID"})
    
    // Define the marginals data (Disaggregated SED marginals)
    marginalData = {FileName: Args.SEDMarginals, Filter: "HH > 0", ID: "TAZ", MatchingID: "PUMA5"}
    o.MarginalFile(marginalData)     
    o.IPUMarginalFile(marginalData)             

    // ***** HH Dimensions *****
    // HH by Size: Define TAZ marginal fields and corresponding values in the seed data
    // Add Marginal Data Spec
    // 'Field': Field from HH seed file for matching (e.g. NP is the HHSize field in the PUMS HH seed)
    // 'Value': The above array, that specifies the marginal fields and how they are mapped to the seed field
    // 'NewFieldName': The field name in the synthesized outout HH file for this variable
    // Also specify the matching field in the seed data
    HHDimSize = {{Name: "HH_siz1", Value: {1, 2}}, 
                 {Name: "HH_siz2", Value: {2, 3}}, 
                 {Name: "HH_siz3", Value: {3, 4}}, 
                 {Name: "HH_siz4", Value: {4, 99}}}
    HHbySizeSpec = {Field: "NP", Value: HHDimSize, NewFieldName: "HHSize"}
    o.AddHHMarginal(HHbySizeSpec)

    // HH by Income (4 categories): Define TAZ marginal fields and corresponding values in the seed data
    HHDimInc = {{Name: "HH_incl" , Value: 1}, 
                {Name: "HH_incml", Value: 2}, 
                {Name: "HH_incmh", Value: 3}, 
                {Name: "HH_inch",  Value: 4}}
    HHbyIncSpec = {Field: "IncomeCategory", Value: HHDimInc, NewFieldName: "IncomeCategory"}
    o.AddHHMarginal(HHbyIncSpec)

    // HH by Number of Workers
    HHDimWrk =   {{Name: "HH_wrk0", Value: {0, 1}}, 
                  {Name: "HH_wrk1", Value: {1, 2}}, 
                  {Name: "HH_wrk2", Value: {2, 3}}, 
                  {Name: "HH_wrk3", Value: {3, 99}}}
    HHbyWrkSpec = {Field: "NumberWorkers", Value: HHDimWrk, NewFieldName: "NumberWorkers"}
    o.AddHHMarginal(HHbyWrkSpec)


    // ***** Add marginals for IPU *****
    // Typically, a good idea to include all of the above HH marginals in the IPU as well
    o.AddIPUHouseholdMarginal(HHbySizeSpec)
    o.AddIPUHouseholdMarginal(HHbyIncSpec)
    o.AddIPUHouseholdMarginal(HHbyWrkSpec)

    // ***** Person Dimensions *****
    // These can only be specified for the IPU procedure. Use three age categories.
    PersonDim =   {{Name: "Kids", Value: {0, 18}}, 
                   {Name: "AdultsUnder65", Value: {18, 65}}, 
                   {Name: "Seniors", Value: {65, 100}}}
    o.AddIPUPersonMarginal({Field: "AgeP", Value: PersonDim, NewFieldName: "Age"})

    // ***** Outputs *****
    // A general note on IPU: 
    // The IPU procedure generally creates a set of weights, one for each TAZ as opposed to a single weight field without IPU
    // These weight fields are used for sampling from the seed
    // Optional outputs include: The IPUIncidenceFile and one weight table for each PUMA
    o.OutputHouseholdsFile = Args.Households
    o.ReportExtraHouseholdField("PUMA", "PUMA")
    o.ReportExtraHouseholdField("HINCP", "HHInc")
    o.OutputPersonsFile = Args.Persons
    o.ReportExtraPersonsField("SEX", "gender") // Add extra field from Person Seed and change the name
    o.ReportExtraPersonsField("RAC1P", "race") // Add extra field from Person seed and change the name
    o.ReportExtraPersonsField("ESR", "EmploymentStatus")
    
    // Optional IPU by-products
    outputFolder = Args.[Output Folder] + "\\resident\\population_synthesis\\"
    o.IPUIncidenceOutputFile = outputFolder + "IPUIncidence.bin"
    o.ExportIPUWeights(outputFolder + "IPUWeights")
    o.Tolerance = 0.01
    ret_value = o.Run()
endMacro


/*
    * Macro produces tabulations of marginals at the TAZ level from the population synthesis output
    * Adds HH summary fields to the synhtesied HH file
*/
Macro "PopSynth Post Process"(Args)

    // Generate tabulations from the synthesis output
    RunMacro("Generate Tabulations", Args)

    objH = CreateObject("AddTables", {TableName: Args.Households})
    vw_hh = objH.TableView
    
    objP = CreateObject("AddTables", {TableName: Args.Persons})
    vw_per = objP.TableView
    
    // Create Balloon Help on synthesized tables
    RunMacro("Set Balloon Help", vw_hh, vw_per)
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "HouseholdID"))
    BuildInternalIndex(GetFieldFullSpec(vw_hh, "ZoneID"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "PersonID"))
    BuildInternalIndex(GetFieldFullSpec(vw_per, "HouseholdID"))
endMacro


Macro "Set Balloon Help"(vw_hh, vw_per)
    // HH Field Descriptions
    desc = null
    desc.ZoneID = "TRM TAZ ID"
    desc.IncomeCategory = "Household Income Category:|1. Income [0, 35K)|2. Income [35K, 70K)|3. Income [70K, 150K)| 4. Income 150K+"
    strct = GetTableStructure(vw_hh, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_hh, strct)
    
    // Person Field descriptions
    desc = null
    desc.Gender = "Gender:|1. Male|2. Female"
    desc.EmploymentStatus = "Employment status recode|1. Civilian employed, at work|2. Civilian employed, with a job but not at work|3. Unemployed|"
    desc.EmploymentStatus = desc.EmploymentStatus + "4. Armed forces, at work|5. Armed forces, with a job but not at work|6. Not in labor force|Missing. N/A (less than 16 years old)"	
    strct = GetTableStructure(vw_per, {"Include Original" : "True"})
    for i = 1 to strct.length do
        fld_name = strct[i][1]
        strct[i][8] = desc.(fld_name)
    end
    ModifyTable(vw_per, strct)
endMacro


Macro "Generate Tabulations"(Args)
    
    outFile = Args.[Synthesized Tabulations]

    // Open HH File and create empty output fields for number of kids, seniors, adults and workers in the HH
    objH = CreateObject("AddTables", {TableName: Args.Households})
    vw_hh = objH.TableView
    modify = CreateObject("CC.ModifyTableOperation", vw_hh)
    modify.FindOrAddField("HHAdultsUnder65", "Long", 12,,)
    modify.FindOrAddField("HHKids", "Long", 12,,)
    modify.FindOrAddField("HHSeniors", "Long", 12,,)
    modify.FindOrAddField("HHWorkers", "Long", 12,,)
    modify.FindOrAddField("HHNWAdults", "Long", 12,,)
    modify.Apply()
    {hhFlds, hhSpecs} = GetFields(vw_hh,)

    objP = CreateObject("AddTables", {TableName: Args.Persons})
    vw_per = objP.TableView

    // Export to In-memory View for faster processing
    vw_hhM = ExportView(vw_hh + "|", "MEM", "HHMem",,{"Indexed Fields": {"HouseholdID"}})
    vw_perM = ExportView(vw_per + "|", "MEM", "PersonMem",,{"Indexed Fields": {"HouseholdID"}})
    objH = null
    objP = null
    
    // Write number of adults, kids, seniors and workers in the synthesized HH table (by aggregation on the synthesized persons)
    expr1 = CreateExpression(vw_perM, "Kid", "if Age < 18 then 1 else 0",)
    expr2 = CreateExpression(vw_perM, "AdultUnder65", "if Age >= 18 and Age < 65 then 1 else 0",)
    expr3 = CreateExpression(vw_perM, "Senior", "if Age >= 65 then 1 else 0",)
    expr4 = CreateExpression(vw_perM, "Worker", "if EmploymentStatus = 1 or EmploymentStatus = 2 or EmploymentStatus = 4 or EmploymentStatus = 5 then 1 else 0",)
    expr5 = CreateExpression(vw_perM, "NWAdults", "if Age >= 18 and Worker = 0 then 1 else 0",)

    // Aggregate person table by 'HouseholdID' and sum the above expression fields
    aggrSpec = {{"Kid", "sum",}, {"AdultUnder65", "sum",}, {"Senior", "sum",}, {"Worker", "sum",}, {"NWAdults", "sum",}}
    vwA =  AggregateTable("MemAggr", vw_perM + "|", "MEM",, "HouseholdID", aggrSpec,)
    {flds, specs} = GetFields(vwA,)
    
    // Join aggregation file to HH table and copy over values
    vwJ = JoinViews("Aggr_HH", specs[1], GetFieldFullSpec(vw_hhM, "HouseholdID"),)
    vecs = GetDataVectors(vwJ + "|", {"Kid", "AdultUnder65", "Senior", "Worker", "NWAdults"}, {OptArray: 1})
    vecsSet.HHKids = vecs.Kid
    vecsSet.HHAdultsUnder65 = vecs.AdultUnder65
    vecsSet.HHSeniors = vecs.Senior
    vecsSet.HHWorkers = vecs.Worker
    vecsSet.HHNWAdults = vecs.NWAdults
    SetDataVectors(vwJ +"|", vecsSet,)
    CloseView(vwJ)
    CloseView(vwA)

    /* Preferred code to replace Lines 190-210, but is much slower. Takes 90 seconds as opposed to 14 seconds for the above snippet
    o = CreateObject("TransCAD.ABM")
    o.TargetFile({ViewName: vw_hhM, ID: "HouseholdID"})
    o.SourceFile({ViewName: vw_perM, ID: "HouseholdID"})
    o.FillTargetField({Filter: "Age < 18", FillField: "HHKids",    DefaultValue: 0})
    o.FillTargetField({Filter: "Age >= 65", FillField: "HHSeniors", DefaultValue: 0})
    o.FillTargetField({Filter: "Age >= 18 and Age < 65", FillField: "HHAdultsUnder65",  DefaultValue: 0})
    o.FillTargetField({Filter: "EmploymentStatus = 1 or EmploymentStatus = 2 or EmploymentStatus = 4 or EmploymentStatus = 5", FillField: "HHWorkers",  DefaultValue: 0})
    o = null*/
    
    // Create Expressions on output HH for tabulations
    specs = null
    specs = {{Fields: {"HH_siz1", "HH_siz2", "HH_siz3", "HH_siz4"}, MatchingField: "HHSize", Levels: {1,2,3,4}},
             {Fields: {"HH_wrk0", "HH_wrk1", "HH_wrk2", "HH_wrk3"},     MatchingField: "NumberWorkers", Levels: {0,1,2,3}},
             {Fields: {"HH_incl", "HH_incml", "HH_incmh", "HH_inch"},   MatchingField: "IncomeCategory", Levels: {1,2,3,4}}
             }
    aggflds = RunMacro("Create Output HH Expressions", vw_hhM, specs)
    aggflds = aggflds + {{"HHSize", "sum",},
                         {"HHAdultsUnder65", "sum",},
                         {"HHKids", "sum",},
                         {"HHSeniors", "sum",},
                         {"HHWorkers", "sum",},
                         {"HHNWAdults", "sum",}} // For HH_Pop and number of adults, kids, seniors and workers

    // Aggregate HH Data
    vw_agg1 = AggregateTable("HHTotals", vw_hhM + "|", "MEM", "Agg1", "ZoneID", aggflds, null)
    ExportView(vw_agg1 + "|", "FFB", outFile,,)
    CloseView(vw_agg1)

    // Change field name in final tabulation file
    obj = CreateObject("AddTables", {TableName: outFile})
    vw = obj.TableView
    modify = CreateObject("CC.ModifyTableOperation", vw)
    modify.ChangeField("HHSize", {Name: "HH_Pop"})
    modify.ChangeField("HHAdultsUnder65", {Name: "AdultsUnder65"})
    modify.ChangeField("HHKids", {Name: "Kids"})
    modify.ChangeField("HHSeniors", {Name: "Seniors"})
    modify.ChangeField("HHWorkers", {Name: "Workers"})
    modify.ChangeField("HHNWAdults", {Name: "NWAdults"})
    modify.Apply()
    obj = null

    // Export the HH In-Memory table back
    ExportView(vw_hhM + "|", "FFB", Args.Households, hhFlds,)
    CloseView(vw_hhM)
    CloseView(vw_perM)
endMacro


// Generates formula fields for tabulations
Macro "Create Output HH Expressions"(vw_hhM, specs)
    aggflds = null
    for spec in specs do
        flds = spec.Fields
        keyFld = spec.MatchingField
        bounds = spec.Levels
        nClasses = flds.length
        for i = 1 to nClasses - 1 do
            CreateExpression(vw_hhM, flds[i], "if " + keyFld + " = " + String(bounds[i]) + " then 1 else 0",)
            aggflds = aggflds + {{flds[i], "sum",}}
        end
        CreateExpression(vw_hhM, flds[nClasses], "if " + keyFld + " >= " + String(bounds[nClasses]) + " then 1 else 0",)
        aggflds = aggflds + {{flds[nClasses], "sum",}}
    end
    Return(aggflds)
endMacro

/*
Creates any additional fields needed by the AO choice model
*/

Macro "Create AO Features" (Args)

    hh_file = Args.Households

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    a_fields =  {
        {"Income1", "Integer", 10, ,,,, "HH is IncomeCategory 1"},
        {"Income2", "Integer", 10, ,,,, "HH is IncomeCategory 2"},
        {"Income3", "Integer", 10, ,,,, "HH is IncomeCategory 3"},
        {"Income4", "Integer", 10, ,,,, "HH is IncomeCategory 4"}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: a_fields})

    v_inccat = GetDataVector(hh_vw + "|", "IncomeCategory", )
    data.[Income1] = if v_inccat = 1 then 1 else 0
    data.[Income2] = if v_inccat = 2 then 1 else 0
    data.[Income3] = if v_inccat = 3 then 1 else 0
    data.[Income4] = if v_inccat = 4 then 1 else 0
    SetDataVectors(hh_vw + "|", data, )
    CloseView(hh_vw)
endmacro

Macro "Calculate Auto Ownership" (Args, trip_types)

    scen_dir = Args.[Scenario Folder]
    ao_coeffs = Args.AOCoeffs
    output_dir = Args.[Output Folder] + "/resident/population_synthesis"
    hh_file = Args.Households

    hh_vw = OpenTable("hh", "FFB", {hh_file})
    a_fields =  {
        {"Autos", "Integer", 10, ,,,, "HH Autos. Result of AO model."}
    }
    RunMacro("Add Fields", {view: hh_vw, a_fields: a_fields})
    CloseView(hh_vw)
    
    primary_spec = {Name: "hh", OField: "ZoneID"}
    obj = CreateObject("PMEChoiceModel", {ModelName: "ao"})
    obj.OutputModelFile = output_dir + "\\auto_ownership.mdl"
    obj.AddTableSource({
        SourceName: "hh",
        File: output_dir + "\\Synthesized_HHs.bin",
        IDField: "HouseholdID"
    })
    obj.AddTableSource({
        SourceName: "se",
        File: scen_dir + "\\output\\sedata\\scenario_se.bin",
        IDField: "TAZ"
    })
    util = RunMacro("Import MC Spec", ao_coeffs)
    obj.AddUtility({UtilityFunction: util})
    obj.AddPrimarySpec(primary_spec)
    obj.AddOutputSpec({ChoicesField: "Autos"})
    obj.RandomSeed = 314159
    obj.Evaluate()

    // Convert coded field/string pairs to simple integers
    hh_vw = OpenTable("hh", "FFB", {hh_file})
    DetachTableTranslation(hh_vw)
    v1 = GetDataVector(hh_vw + "|", "Autos", )
    v2 = v1 - 1
    SetDataVector(hh_vw + "|", "Autos", v2, )
    CloseView(hh_vw)
endmacro