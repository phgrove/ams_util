;---------------------------
;Get current session details
;---------------------------
sess        = asiGetCurrentSession() 

;Netlist Lib/cell/view
libName     = asiGetDesignLibName(sess)
cellName    = asiGetDesignCellName(sess)
viewName    = asiGetDesignViewName(sess)

;design vars as list from the current session
des_vars    = asiGetDesignVarList(sess)

;netlist location of current session
netlist_dir = asiGetNetlistDir(sess) 

;------------------------------
;Create a netlist in a tmp area
;------------------------------
simulator('ams)
design( libName cellName viewName "r") 

;Set UNL netlist
ocnAmsSetUnlNetlister() 

;Other options might need setting like portDril, HDL package manager
;a lot we have set in a template Maestro view so are default. 
;These need to be temp changes so need to store current value and reset
;them at the end. These will be needed to ensure the AMS netlister runs
;the assembly point. 


;Add design varaibles so cds_globals is correct.
foreach( des_var des_vars
   desVar(nth(0 des_var) nth(1 des_var))
)

;Netlist to a temp folder
netlist_tmp_folder  = strcat(getTempDir() "/" getShellEnvVar("USER") "/netlist")
createDirHier(netlist_tmp_folder) 
;printf("netlist_folder = %s\n" netlist_tmp_folder)

;Set netlist dir
netlistDir(netlist_tmp_folder)
resultsDir(strcat(netlist_tmp_folder "/../"))

;Generate netlist and runSimulation file
createNetlist( ?recreateAll t ?display nil )
asiGetSimulationRunCommand( asiGetCurrentSession() )

;call translator and copy results to simulation run folder
;lib:cell:view just so it has some useful name. cdslib needed to for regex on env
cmd = strcat("~/unl2lrm.pl -lib " libName " -cell " cellName " -view " viewName " -cdslib " getWorkingDir() "/cds.lib -unl_dir " netlist_tmp_folder "/../ -outdir " netlist_dir "/snps_netlist -debug" )
info(cmd "\n")
ipc = ipcBeginProcess(cmd)  
if(ipcWait(ipc, 15, 60) == 0 then
  error(strcat("Command failed:\n" ipcReadProcess(ipc)))
else
  info(strcat("Converted netlist in " ipcReadProcess(ipc)))
)

