;; unl2lrm_asiNetlist.il
;; 
;; Override PrimeSim XA asiNetlist to use UNL (AMS) netlisting
;; followed by UNL-to-LRM translation via unl2lrm_asiNetlist.pl.
;;
;; Load AFTER spiceADE package to redefine the netlist method.
;;
;; Usage:
;;   ;; In .cdsinit, after spiceADE loads:
;;   load("/path/to/directory/containing/this/file/unl2lrm_asiNetlist.il")
;;
;; ----------------------------------------------------------------
;; Redefine asiNetlist for PrimeSim XA
;; ----------------------------------------------------------------

;; ---------------------------
;; Get folder skill/perl script in
;; ---------------------------
pcreMatchp("(.*/)?.*" simplifyFilename(get_filename(piport)))
unl2lrm_asiNetlist_dir  = (pcreSubstitute "\\1")

;; ---------------------------
;; Don't show a warning this method is been redefined!
;; ---------------------------
muffleWarnings(

;; ---------------------------
;; Define new implementation of the asiNetlist method
;; ---------------------------
defmethod( asiNetlist ((session PrimeSim_XA_session))
    let((sess libName cellName viewName desVars results_dir netlist_tmp_folder 
         cmd ipc ams_session)
    
        ;; ---------------------------
        ;; Get current session details
        ;; ---------------------------
        sess        = asiGetCurrentSession()

        ;; Netlist Lib/cell/view
        libName     = asiGetDesignLibName(sess)
        cellName    = asiGetDesignCellName(sess)
        viewName    = asiGetDesignViewName(sess)

        ;; design vars as list from the current session
        desVars     = asiGetDesignVarList(sess)
        
        ;; Model list
        modelList   = asiGetModelLibSelectionList(session)

        ;; Results folder for current session
        results_dir = asiGetResultsDir(sess)

        ;; Output useful message to log file
        info(strcat("Ruuning UNL on " libName ":" cellName ":" viewName " to netlist folder " results_dir "\n"))

        ;; ------------------------------
        ;; Create a netlist in a tmp area
        ;; ------------------------------
        simulator('ams)
        design(libName cellName viewName "r")
        
        ;; Handle to current session
        ams_session = asiGetCurrentSession()
        
        ;; Set UNL netlist
        ocnAmsSetUnlNetlister()

        ;; Other options might need setting like portDril, HDL package manager
        ;; a lot we have set in a template Maestro view so are default.
        ;; These need to be temp changes so need to store current value and reset
        ;; them at the end. These will be needed to ensure the AMS netlister runs
        ;; the assembly point.

        ;; Add Models after deleting all other in the detault setup.
        asiRemoveAllModelLibSelection(ams_session)
        foreach(model modelList
            asiAddModelLibSelection(ams_session 
                                    asiGetModelLibFile(model)
                                    asiGetModelLibSection(model)
                                    )
        )

        ;; Add design varaibles so cds_globals is correct.
        foreach( desVar desVars
           desVar(nth(0 desVar) nth(1 desVar))
        )

        ;; Netlist to a temp folder
        ;; netlist_tmp_folder  = makeTempFileName(strcat(getTempDir() "/" getShellEnvVar("USER") "/netlist"))
        netlist_tmp_folder  = asiGetNetlistDir(sess)
        createDirHier(netlist_tmp_folder)
        info(strcat("UNL2LRM: tmp folder for netlisting " netlist_tmp_folder "\n"))

        ;; Set netlist dir
        netlistDir(netlist_tmp_folder)
        resultsDir(strcat(netlist_tmp_folder "/../"))

        ;; Generate netlist and runSimulation file
        createNetlist( ?recreateAll t ?display nil )
        asiGetSimulationRunCommand( ams_session )

        ;; call translator and copy results to simulation run folder
        ;; lib:cell:view just so it has some useful name. cdslib needed to for regex on env
        cmd = strcat(unl2lrm_asiNetlist_dir "/unl2lrm_asiNetlist.pl"
                     " -lib "             libName 
                     " -cell "            cellName 
                     " -view "            viewName 
                     " -cdslib " getWorkingDir() "/cds.lib"
                     " -unl_dir " netlist_tmp_folder "/../"
                     " -outdir " results_dir "/snps_netlist" 
                     " -debug")
        info(strcat(cmd "\n"))
        ipc = ipcBeginProcess(cmd)
        if(ipcWait(ipc, 15, 60) == 0 then
          error(strcat("Command failed:\n" ipcReadProcess(ipc)))
        else
          info(strcat("Converted netlist in " results_dir "/netlist" ))
        )
        t ;; return sucess
    ) ; let
) ; defmethod

info("UNL2LRM: Redefined asiNetlist for PrimeSim_XA_session\n")

) ; muffleWarnings
