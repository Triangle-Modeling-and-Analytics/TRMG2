/*
University Model
*/

Macro "University" (Args)
    RunMacro("University Productions", Args)
    RunMacro("University Attractions", Args)
    RunMacro("University Balance Ps and As", Args)
    RunMacro("University TOD", Args)
    RunMacro("University Gravity", Args)
    RunMacro("University Combine Matrix", Args)
    RunMacro("University Directionality", Args)
    ShowMessage("done")
    return(1)
endmacro

/*
Calculate university productions
*/

Macro "University Productions" (Args)
    se_file = Args.SE
    production_rate_file = Args.[Input Folder] + "\\university\\university_production_rates.csv"

    // TODO-AK: delete the hard-coded paths (used for testing)
    se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
    production_rate_file = "D:\\Models\\TRMG2\\master\\university\\university_production_rates.csv"

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    se_vw = OpenTable("se", "FFB", {se_file})

    data = GetDataVectors(
        se_vw + "|",
        {
            "StudGQ_NCSU",
            "StudGQ_UNC",
            "StudGQ_DUKE",
            "StudGQ_NCCU",
            "StudOff_NCSU",
            "StudOff_UNC",
            "StudOff_DUKE",
            "StudOff_NCCU"
        },
        {OptArray: TRUE}
    )

    // read university production rate file
    rate = RunMacro("Read Parameter File", {
        file: production_rate_file,
        names: "variable",
        values: "rate"
    })

    SetView(se_vw)

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        //UHC: Home-Based-Campus
        //UHO: Home-Based-Other
        //UCO: Campus-Based-Other
        //UC1: On-Campus
        //UCC: Inter-Campus
        //UOO: University student Other-Other

        production_uhc_on = data.("StudGQ_" + campus) * rate.Prod_Rate_On_UHC
        production_uho_on = data.("StudGQ_" + campus) * rate.Prod_Rate_On_UHO
        production_uco_on = data.("StudGQ_" + campus) * rate.Prod_Rate_On_UCO
        production_uc1_on = data.("StudGQ_" + campus) * rate.Prod_Rate_On_UC1
        production_ucc_on = data.("StudGQ_" + campus) * rate.Prod_Rate_On_UCC

        production_uhc_off = data.("StudOff_" + campus) * rate.Prod_Rate_Off_UHC
        production_uho_off = data.("StudOff_" + campus) * rate.Prod_Rate_Off_UHO
        production_uco_off = data.("StudOff_" + campus) * rate.Prod_Rate_Off_UCO
        production_uc1_off = data.("StudOff_" + campus) * rate.Prod_Rate_Off_UC1
        production_ucc_off = data.("StudOff_" + campus) * rate.Prod_Rate_Off_UCC

        a_fields = {
            {"ProdOn_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OnCampus Production"},
            {"ProdOn_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OnCampus Production"},
            {"ProdOn_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO OnCampus Production"},
            {"ProdOn_UC1_" + campus, "Real", 10, 2, , , , campus + " UC1 OnCampus Production"},
            {"ProdOn_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC OnCampus Production"},
            {"ProdOff_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OffCampus Production"},
            {"ProdOff_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OffCampus Production"},
            {"ProdOff_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO OffCampus Production"},
            {"ProdOff_UC1_" + campus, "Real", 10, 2, , , , campus + " UC1 OffCampus Production"},
            {"ProdOff_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC OffCampus Production"}
        }
        RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

        SetDataVector(se_vw + "|", "ProdOn_UHC_" + campus, production_uhc_on, )
        SetDataVector(se_vw + "|", "ProdOn_UHO_" + campus, production_uho_on, )
        SetDataVector(se_vw + "|", "ProdOn_UCO_" + campus, production_uco_on, )
        SetDataVector(se_vw + "|", "ProdOn_UC1_" + campus, production_uc1_on, )
        SetDataVector(se_vw + "|", "ProdOn_UCC_" + campus, production_ucc_on, )

        SetDataVector(se_vw + "|", "ProdOff_UHC_" + campus, production_uhc_off, )
        SetDataVector(se_vw + "|", "ProdOff_UHO_" + campus, production_uho_off, )
        SetDataVector(se_vw + "|", "ProdOff_UCO_" + campus, production_uco_off, )
        SetDataVector(se_vw + "|", "ProdOff_UC1_" + campus, production_uc1_off, )
        SetDataVector(se_vw + "|", "ProdOff_UCC_" + campus, production_ucc_off, )

    end

    CloseView(se_vw)

endmacro

/*
Calculate university attractions
*/

Macro "University Attractions" (Args)
    se_file = Args.SE
    rate_file = Args.[Input Folder] + "\\university\\university_attraction_rates.csv"

    // TODO-AK: delete the hard-coded paths (used for testing)
    se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
    rate_file = "D:\\Models\\TRMG2\\master\\university\\university_attraction_rates.csv"

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    se_vw = OpenTable("se", "FFB", {se_file})

    data = GetDataVectors(
        se_vw + "|",
        {
            "StudGQ_NCSU",
            "StudGQ_UNC",
            "StudGQ_DUKE",
            "StudGQ_NCCU",
            "StudOff_NCSU",
            "StudOff_UNC",
            "StudOff_DUKE",
            "StudOff_NCCU",
            "BuildingS_NCSU",
            "BuildingS_UNC",
            "BuildingS_DUKE",
            "BuildingS_NCCU",
            "Retail"
        },
        {OptArray: TRUE}
    )

    // read university attraction model file for coefficients
    uco_on_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uco_on"})
    uho_on_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uho_on"})
    uco_off_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uco_off"})
    uho_off_coeff = RunMacro("Read Parameter File", {file: rate_file, names: "variable", values: "uho_off"})

    SetView(se_vw)

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        //share of campus bldg sqft among zones
        proportion_bldg_sqft_campus = data.("BuildingS_" + campus) / data.("BuildingS_" + campus).sum()

        // on-campus attractions
        attraction_uho_on = uho_on_coeff.intercept +
            uho_on_coeff.retail_employment * data.Retail +
            uho_on_coeff.student_off_campus * data.("StudOff_" + campus)

        attraction_uco_on = uco_on_coeff.intercept +
            uco_on_coeff.retail_employment * data.Retail +
            uco_on_coeff.student_off_campus * data.("StudOff_" + campus)

        attraction_uhc_on = proportion_bldg_sqft_campus

        attraction_ucc_on = proportion_bldg_sqft_campus

        // off-campus attractions
        attraction_uho_off = uho_off_coeff.intercept +
            uho_off_coeff.retail_employment * data.Retail +
            uho_off_coeff.student_off_campus * data.("StudOff_" + campus)

        attraction_uco_off = uco_off_coeff.intercept +
            uco_off_coeff.retail_employment * data.Retail +
            uco_off_coeff.student_off_campus * data.("StudOff_" + campus)

        attraction_uhc_off = proportion_bldg_sqft_campus

        attraction_ucc_off = proportion_bldg_sqft_campus

        a_fields = {
            {"AttrOn_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OnCampus Attraction"},
            {"AttrOn_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OnCampus Attraction"},
            {"AttrOn_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO OnCampus Attraction"},
            {"AttrOn_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC OnCampus Attraction"},
            {"AttrOff_UHC_" + campus, "Real", 10, 2, , , , campus + " UHC OffCampus Attraction"},
            {"AttrOff_UHO_" + campus, "Real", 10, 2, , , , campus + " UHO OffCampus Attraction"},
            {"AttrOff_UCO_" + campus, "Real", 10, 2, , , , campus + " UCO OffCampus Attraction"},
            {"AttrOff_UCC_" + campus, "Real", 10, 2, , , , campus + " UCC OffCampus Attraction"}
        }
        RunMacro("Add Fields", {view: se_vw, a_fields: a_fields})

        SetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, attraction_uhc_on, )
        SetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, attraction_uho_on, )
        SetDataVector(se_vw + "|", "AttrOn_UCO_" + campus, attraction_uco_on, )
        SetDataVector(se_vw + "|", "AttrOn_UCC_" + campus, attraction_ucc_on, )

        SetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, attraction_uhc_off, )
        SetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, attraction_uho_off, )
        SetDataVector(se_vw + "|", "AttrOff_UCO_" + campus, attraction_uco_off, )
        SetDataVector(se_vw + "|", "AttrOff_UCC_" + campus, attraction_ucc_off, )
    end

endmacro

/*
Balance university production and attraction
*/

Macro "University Balance Ps and As" (Args)
    se_file = Args.SE

    // TODO-AK: delete the hard-coded paths (used for testing)
    se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"

    se_vw = OpenTable("se", "FFB", {se_file})
    SetView(se_vw)

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    for c = 1 to campus_list.length do
        campus = campus_list[c]

        // on-campus
        production_uhc_on = GetDataVector(se_vw + "|", "ProdOn_UHC_" + campus, )
        production_uho_on = GetDataVector(se_vw + "|", "ProdOn_UHO_" + campus, )
        production_uco_on = GetDataVector(se_vw + "|", "ProdOn_UCO_" + campus, )
        production_ucc_on = GetDataVector(se_vw + "|", "ProdOn_UCC_" + campus, )

        attraction_uhc_on = GetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, )
        attraction_uho_on = GetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, )
        attraction_uco_on = GetDataVector(se_vw + "|", "AttrOn_UCO_" + campus, )
        attraction_ucc_on = GetDataVector(se_vw + "|", "AttrOn_UCC_" + campus, )

        production_uhc_on_total = VectorStatistic(production_uhc_on, "sum", )
        production_uho_on_total = VectorStatistic(production_uho_on, "sum", )
        production_uco_on_total = VectorStatistic(production_uco_on, "sum", )
        production_ucc_on_total = VectorStatistic(production_ucc_on, "sum", )

        attraction_uhc_on_total = VectorStatistic(attraction_uhc_on, "sum", )
        attraction_uho_on_total = VectorStatistic(attraction_uho_on, "sum", )
        attraction_uco_on_total = VectorStatistic(attraction_uco_on, "sum", )
        attraction_ucc_on_total = VectorStatistic(attraction_ucc_on, "sum", )

        // balancing to productions
        attraction_uhc_on = attraction_uhc_on * production_uhc_on_total/attraction_uhc_on_total
        attraction_uho_on = attraction_uho_on * production_uho_on_total/attraction_uho_on_total
        attraction_uco_on = attraction_uco_on * production_uco_on_total/attraction_uco_on_total
        attraction_ucc_on = attraction_ucc_on * production_ucc_on_total/attraction_ucc_on_total

        SetDataVector(se_vw + "|", "AttrOn_UHC_" + campus, attraction_uhc_on, )
        SetDataVector(se_vw + "|", "AttrOn_UHO_" + campus, attraction_uho_on, )
        SetDataVector(se_vw + "|", "AttrOn_UCO_" + campus, attraction_uco_on, )
        SetDataVector(se_vw + "|", "AttrOn_UCC_" + campus, attraction_ucc_on, )

        // off-campus
        production_uhc_off = GetDataVector(se_vw + "|", "ProdOff_UHC_" + campus, )
        production_uho_off = GetDataVector(se_vw + "|", "ProdOff_UHO_" + campus, )
        production_uco_off = GetDataVector(se_vw + "|", "ProdOff_UCO_" + campus, )
        production_ucc_off = GetDataVector(se_vw + "|", "ProdOff_UCC_" + campus, )

        attraction_uhc_off = GetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, )
        attraction_uho_off = GetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, )
        attraction_uco_off = GetDataVector(se_vw + "|", "AttrOff_UCO_" + campus, )
        attraction_ucc_off = GetDataVector(se_vw + "|", "AttrOff_UCC_" + campus, )

        production_uhc_off_total = VectorStatistic(production_uhc_off, "sum", )
        production_uho_off_total = VectorStatistic(production_uho_off, "sum", )
        production_uco_off_total = VectorStatistic(production_uco_off, "sum", )
        production_ucc_off_total = VectorStatistic(production_ucc_off, "sum", )

        attraction_uhc_off_total = VectorStatistic(attraction_uhc_off, "sum", )
        attraction_uho_off_total = VectorStatistic(attraction_uho_off, "sum", )
        attraction_uco_off_total = VectorStatistic(attraction_uco_off, "sum", )
        attraction_ucc_off_total = VectorStatistic(attraction_ucc_off, "sum", )

        // balancing to productions
        attraction_uhc_off = attraction_uhc_off * production_uhc_off_total/attraction_uhc_off_total
        attraction_uho_off = attraction_uho_off * production_uho_off_total/attraction_uho_off_total
        attraction_uco_off = attraction_uco_off * production_uco_off_total/attraction_uco_off_total
        attraction_ucc_off = attraction_ucc_off * production_ucc_off_total/attraction_ucc_off_total

        SetDataVector(se_vw + "|", "AttrOff_UHC_" + campus, attraction_uhc_off, )
        SetDataVector(se_vw + "|", "AttrOff_UHO_" + campus, attraction_uho_off, )
        SetDataVector(se_vw + "|", "AttrOff_UCO_" + campus, attraction_uco_off, )
        SetDataVector(se_vw + "|", "AttrOff_UCC_" + campus, attraction_ucc_off, )

    end

    CloseView(se_vw)

endmacro

/*
Split university balanced productions and attractions by time periods
*/

Macro "University TOD" (Args)
    se_file = Args.SE
    tod_file = Args.[Input Folder] + "\\university\\university_tod.csv"

    // TODO-AK: delete the hard-coded paths (used for testing)
    se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
    tod_file = "D:\\Models\\TRMG2\\master\\university\\university_tod.csv"

    se_vw = OpenTable("se", "FFB", {se_file})

    {drive, folder, name, ext} = SplitPath(tod_file)

    RunMacro("Create Sum Product Fields", {
        view: se_vw, factor_file: tod_file,
        field_desc: "University Productions and Attractions by Time of Day|See " + name + ext + " for details."
    })

    CloseView(se_vw)
endmacro

/*
University Gravity Distribution
*/

Macro "University Gravity" (Args)
    se_file = Args.SE
    param_file = Args.[Input Folder] + "\\university\\university_gravity.csv"
    skim_file =  Args.[Output Folder] + "\\skims\\roadway\\skim_sov_AM.mtx"
    university_matrix_file = Args.[Output Folder] + "\\university\\university_pa_trips.mtx"

    // TODO-AK: delete the hard-coded paths (used for testing)
    se_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\sedata\\scenario_se.bin"
    param_file = "D:\\Models\\TRMG2\\master\\university\\university_gravity.csv"
    skim_file =  "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\skims\\roadway\\skim_sov_AM.mtx"
    university_matrix_file = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\university\\university_pa_trips.mtx"

    opts = null
    opts.se_file = se_file
    opts.param_file = param_file
    opts.skim_file = skim_file
    opts.output_matrix = university_matrix_file
    RunMacro("Gravity", opts)

endmacro

/*
Combine university trips for all campus and create period specific matrices
*/

Macro "University Combine Matrix" (Args)
    trips_dir = Args.[Output Folder] + "\\university\\"
    periods = Args.periods

    // TODO-AK: delete the hard-coded paths (used for testing)
    trips_dir = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\university\\"
    periods = {"AM", "MD", "PM", "NT"}

    campus_list = {"NCSU", "UNC", "DUKE", "NCCU"}

    university_mtx_file = trips_dir + "university_pa_trips.mtx"

    out_core_names = {"UHC", "UHO", "UCO", "UCC"}

    for period in periods do
        out_mtx_file = trips_dir + "university_pa_trips_" + period + ".mtx"
        if GetFileInfo(out_mtx_file) <> null then DeleteFile(out_mtx_file)

        univ_mtx = OpenMatrix(university_mtx_file, )
        mc = CreateMatrixCurrency(univ_mtx,,,,)

        matOpts = {{"File Name", out_mtx_file}, {"Label", "University " + period + " Trips Matrix"}, {"File Based", "Yes"}, {"Tables", out_core_names}}

        out_mtx = CopyMatrixStructure({mc}, matOpts)

        mc = null
        univ_mtx = null
        out_mtx = null

        univ_mtx = CreateObject("Matrix")
        univ_mtx.LoadMatrix(university_mtx_file)

        out_mtx = CreateObject("Matrix")
        out_mtx.LoadMatrix(out_mtx_file)

        cores = univ_mtx.data.cores
        out_cores = out_mtx.data.cores

        out_cores.("UHC") := 0
        out_cores.("UHO") := 0
        out_cores.("UCO") := 0
        out_cores.("UCC") := 0

        for campus in campus_list do
            out_cores.("UHC") := out_cores.("UHC") + Nz(cores.("UHC_" + campus + "_" + period))
            out_cores.("UHO") := out_cores.("UHO") + Nz(cores.("UHO_" + campus + "_" + period))
            out_cores.("UCO") := out_cores.("UCO") + Nz(cores.("UCO_" + campus + "_" + period))
            out_cores.("UCC") := out_cores.("UCC") + Nz(cores.("UCC_" + campus + "_" + period))
        end

    end

    cores = null
    out_cores = null
    univ_mtx = null
    out_mtx = null

    DeleteFile(university_mtx_file)
endmacro

/*
Convert from PA to OD format
*/

Macro "University Directionality" (Args)
    trips_dir = Args.[Output Folder] + "\\university\\"
    dir_factor_file = Args.[Input Folder] + "\\university\\university_directionality.csv"
    periods = Args.periods

    // TODO-AK: delete the hard-coded paths (used for testing)
    trips_dir = "D:\\Models\\TRMG2\\scenarios\\base_2016\\output\\university\\"
    dir_factor_file = "D:\\Models\\TRMG2\\master\\university\\university_directionality.csv"
    periods = {"AM", "MD", "PM", "NT"}

    fac_vw = OpenTable("dir", "CSV", {dir_factor_file})

    dir_factors = RunMacro("Read Parameter File", {
        file: dir_factor_file,
        names: "period",
        values: "pa_factor"
    })

    for period in periods do
        pa_matrix_file = trips_dir + "university_pa_trips_" + period + ".mtx"
        od_matrix_file = trips_dir + "university_trips_" + period + ".mtx"
        od_transpose_matrix_file = trips_dir + "university_transpose_trips_" + period + ".mtx"

        CopyFile(pa_matrix_file, od_matrix_file)

        mat = OpenMatrix(od_matrix_file, )
        tmat = TransposeMatrix(mat, {
            {"File Name", od_transpose_matrix_file},
            {"Label", "Transposed Trips"},
            {"Type", "Double"}}
        )

        mat = null
        tmat = null

        mtx = CreateObject("Matrix")
        mtx.LoadMatrix(od_matrix_file)
        mtx_core_names = mtx.data.CoreNames
        cores = mtx.data.cores

        t_mtx = CreateObject("Matrix")
        t_mtx.LoadMatrix(od_transpose_matrix_file)
        t_cores = t_mtx.data.cores

        pa_factor = dir_factors.(period)

        for core_name in mtx_core_names do
            cores.(core_name) := Nz(cores.(core_name)) * pa_factor + Nz(t_cores.(core_name)) * (1 - pa_factor)
        end

        cores = null
        t_cores = null
        mtx = null
        t_mtx = null

        DeleteFile(od_matrix_file)
        DeleteFile(od_transpose_matrix_file)

    end

endmacro
