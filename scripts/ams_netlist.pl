#!/usr/bin/env perl

#################################################################################################
## 
## MIT No Attribution
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this
## software and associated documentation files (the "Software"), to deal in the Software
## without restriction, including without limitation the rights to use, copy, modify,
## merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
## permit persons to whom the Software is furnished to do so.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
## INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
## PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
## HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
## OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
## SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
## 
#################################################################################################

##########################################################
#                         Description                     
# A script for converting the Cadence UNL-AMS netlister   
# output into some files that can be read in by Synopsys  
#                                                         
# Output should be LRM compliant so any tool can use it!                         
#                                                         
##########################################################

#Perl Libraries
use strict;
use warnings;
use File::Basename;
use File::Spec;
use Getopt::Long;
use Pod::Usage;

############################################################
#Create a hash of hash that stores the UNL-AMS data as
#lib(s)->cell(s)->viewType(s)->view(s)->file/count
#If count is 0 then it is the first lib.cell. A count > 0
#means it is a different view of the lib.cell and needs
#to be in its own library.
#
#Each textInput must be one module per file else the system
#fails, so the output of cds2ams can't be used at the moment.
#Instead this routine now calls runams directly and uses 
#its output to create the LRM compliant netlist.
############################################################
my %libs;

############################################################
#Creates a list of the library Names and files for the 
#lib.map file.
############################################################
my %libmap_mapping;

############################################################
#Creates a hash lib:cell and a counter saying how many views
#have been found so the library naming is sorted out. 
#Probably could do all this in the %libs has file but not
#sure how!
############################################################
my %libs_cnt;

############################################################
#General Variables used in the routines.
############################################################
my $ext;
my $file;
my %gen_files;
my $log;

############################################################
#Options for the script
############################################################
my $debug;  
my $verbose;
# Design to Netlist from Virtuoso
my $lib              = "";                                                  #Virtuoso DFII library name            
my $cell             = "";                                                  #Virtuoso DFII cell name            
my $view             = "";                                                  #Virtuoso DFII HED config name            
my $cdslib_path;                                                            #Virtuoso cds.lib path
my $virtuoso_root    = "$ENV{CDSINSTALL_PATH}/../../";                      #Root of Virtuoso installation folder used to map AMS_CIC_HIER
# Input files that are the standard from runams
my $main_neltist_file= "netlist.vams";                                      #Main schematic->VAMS netlist
my $textinputs       = "textInputs";                                        #Name of textInputs file from runams
my $amsbind          = ".amsbind.scs";                                      #Name of amsbind file from runams
my $xrunargs ;
my $instbindtable    = ".instBindInfoTable";                                #Name of Instance binding table file from runams
# Output files 
my $top              = "config_ams_top";                                    #Name for Verilog Configuration Top cell
my $outdir           = "./snps";                                            #Output folder 
my $netlist_path     = "./snps";                                            #Path to netlist folder
my $verilog_config   = "verilog.config.sv";                                 #Verilog Configuration File name
my $lib_map_file     = "lib.map";                                           #Verilog lib.map File name
# Options fopr some Cadence xLRM constructs
my $no_netsets;
my $no_mfactor;

#######################################################################################
#Get command line options
#######################################################################################
GetOptions (#General inputs for all netlisting                   
            "lib=s"                 => \$lib,
            "cell=s"                => \$cell,
            "view=s"                => \$view,
            
            #Set where the final converted netlist should be places.
            "outdir=s"              => \$outdir, 
            
            #Refine name and files from default.
            "vconfig_name=s"        => \$top,
            "vconfig_file=s"        => \$verilog_config,
            "libmap_name=s"         => \$lib_map_file,

            #control some xLRM constructs            
            "no_netsets"            => \$no_netsets, 
            "no_mfactor"            => \$no_mfactor ,    

            #cds setting
            "cdslib|cds_lib=s"      => \$cdslib_path, 
            "virtuoso_root=s"       => \$virtuoso_root,            
            
            #General debug
            "verbose"               => \$verbose,             
            "debug"                 => \$debug,                
            "help"                  => sub{ pod2usage(-verbose => 2) })
    ||  pod2usage(-verbose => 2);  

if($lib         eq '') { pod2usage(-msg => "Error : Library name not specified.",             -verbose => 0); }
if($cell        eq '') { pod2usage(-msg => "Error : Cell name not specified.",                -verbose => 0); }
if($view        eq '') { pod2usage(-msg => "Error : View name not specified.",                -verbose => 0); }
if($cdslib_path eq '') { pod2usage(-msg => "Error : cdslib not specified.",                   -verbose => 0); }
        
#######################################################################################
#Check cdslib path as there are various systems used on different sites
#######################################################################################
if(!(-r $cdslib_path) || (-d $cdslib_path)) { 
    if(!(-r ${cdslib_path}."/cds.lib")) { pod2usage(-msg => "Error : cds.lib file not found \"$cdslib_path\".",-verbose => 0); }
    else                                { ${cdslib_path} = ${cdslib_path}."/cds.lib"; }
}

#Get the full path to the cds.lib file.
$cdslib_path = File::Spec->rel2abs($cdslib_path);

#Get directory to cds.lib as some of the tools must be run in that folder.
my $virtuoso_path = dirname($cdslib_path);

#######################################################################################
#Run netlister as we have to use raw output for this to work.
####################################################################################### 
my $netlist_location = "/tmp/".&generate_random_string(11);
print "Netlist location: $netlist_location\n";
`mkdir $netlist_location`;
#.cdsenv file passed to runams for any specific opeiotns
`touch $netlist_location/.cdsenv`;
#-portdrill require Virtuso Studio 23.1 ISR9 or later to work correctly. It needs unlPortDrill="execpt top" and printNetSetForPortDrill=t
`echo 'ams.compilerOpts      nowarnVlog                    string   "DLNOHV,NSVCER,DLCLIB,DLCOMBR"' >> $netlist_location/.cdsenv`;
`echo 'ams.netlisterOpts     iprobeGenPlace                string   "netlist.vams"' 				>> $netlist_location/.cdsenv`;
`echo 'ams.netlisterOpts     printNetSetForPortDrill       boolean  t'								>> $netlist_location/.cdsenv`;
`echo 'ams.netlisterOpts     unlPorDrill                   string   except top"' 					>> $netlist_location/.cdsenv`;
my $command = "runams -lib $lib -cell $cell -view $view -netlist all -cdsenv ${netlist_location}/.cdsenv -cdslib $cdslib_path -log ${netlist_location}/run.log -rundir ${netlist_location} -portdrill all -netlisteropts 'amsPortConnectionByNameOrOrder=name:useSpectreInfo=spectre veriloga spice' -savescripts -64";
system("cd $virtuoso_path; $command");
$main_neltist_file= "$netlist_location/netlist/$main_neltist_file"; 
$textinputs       = "$netlist_location/netlist/$textinputs";   
$amsbind          = "$netlist_location/netlist/$amsbind"; 
$log              = "${lib}.${cell}.${view}.log";
$xrunargs         = "$netlist_location/netlist/xrunArgs";
$instbindtable    = "$netlist_location/netlist/$instbindtable";
print "Netlist location:    $netlist_location\n";

if(!-e $main_neltist_file) {
    print "Netlisting failed. Look in $netlist_location for possible reasons.";
    die;
}

#######################################################################################
#Create a temp folder location to use for the splitting up of the netlist.vams file
####################################################################################### 
my $temp_location = "/tmp/".&generate_random_string(11);
`mkdir $temp_location`;
`mkdir $temp_location/merged`;
print "Temp location:    $temp_location\n";

#######################################################################################
#Create output folder that processed files will go into
####################################################################################### 
$outdir = File::Spec->rel2abs($outdir);
`rm -rf $outdir/*`;`rm -rf $outdir/.*`;
`mkdir $outdir`;
print "Output location:  $outdir\n";

#######################################################################################
#Split netlist.vams up into lib.cell.view - Does not support `noworklib `noview
####################################################################################### 
print "Processing main netlist\n";
#Record start time to use later on to check how long this processing took.
my $start_time        = time();
open(FILE, "<",$main_neltist_file) or die "Can't open $main_neltist_file";
my $out;
my $filename;
#To support the -export system in runams.
my $ip_prefix = (($command =~ m/-export\s+/) && ($command =~ m/-iplabel\s+(.*?)\s+/)) ? "${1}_":"";
while(<FILE>) {
    chomp;
    my $line = $_;
    
    #Extract details from comment field added above every translated schematic
    if ($line =~ m/^\/\/\s+Library\s+-\s+(\S+),\s+Cell\s+-\s+(\S+),\s+View\s+-\s+(\S+)/){
        my $lib =$1;
        my $cell=$2;
        my $view=$3; 
        if(defined $out) {
            #Close the file
            close($out);
            
            #Move tmp file to real file name
            `mv ${temp_location}/tmp.vams ${temp_location}/$filename`;
            
            #Comment out Cadence attributes But these could be on multiple lines so needs to be called as a perl onliner
            if(defined $no_netsets) {
                `perl -0777 -pi -e 's/(\\(\\*  integer cds_net_set .*?\\*\\))/\\/\\* \$1 \\*\\//gms' $filename`;
                `perl -0777 -pi -e 's/(\\(\\*  integer inh_conn_prop_name  .*?\\*\\))/\\/\\* \$1 \\*\\//gms' $filename`;
            }
        }
        #Set next file name and open the tmp file again.
        $filename = "${ip_prefix}${lib}.${cell}.$view.vams";               
        open($out, ">${temp_location}/tmp.vams") or die "Failed to write to file tmp.vams";
        next;
    }

    #The `worklib should be the same as the $lib found from the comment but just in case.
    if($line =~ m/^`worklib\s+(\w+)\s*$/){
         my $lib = $1;
         $filename =~ s/^${ip_prefix}\w+\./${ip_prefix}${lib}\./;
         $line     =~ s/^`worklib /\/\/`worklib /;
    }            
    $line =~ s/^`noworklib /\/\/`noworklib /;
    
    #The `view sets the actual view name to be used and not from the comment in the netlist.
    if($line =~ m/^`view\s+(\w+)\s*$/){
         my $view = $1;
         $filename =~ s/\.\w+\.vams/\.${view}\.vams/; 
         $line =~ s/^`view/\/\/`view /;                
    }           
    $line =~ s/^`noview /\/\/`noview /;
    
    #Not needed as timescale should only be in module with text views.
    $line =~ s/^`timescale /\/\/`timescale /;
    
    #This is a Cadence attribute that i am not sure what its used for.
    $line =~ s/^\(\* cds_ams_/\/\/\(\* cds_ams_/;

    #Hack iprobe to cds_alias as iprobe is a built in Spectre primative. Really XA should support any spectre
    #primative in a Verilog-AMS file that they support in the spectre netlist
    $line =~ s/^iprobe /cds_alias #\(1\) /;

    #Convert real2int to $itor as this is in the LRM but for digital context only. However a parameter
    #has no context so is allowed. Verilog-AMS 2023 made $itor available for digital and analog context.
    $line =~ s/real2int\(/\$itor\(/g;

    #m parameters on instances be set to $mfactor as per the LRM. This works in conjunction with
    #the value of the passed_mfactor attribute
    if(defined $no_mfactor) { $line =~ s/(\(\*\s*integer passed_mfactor = \"m\";\s*\*\))/\/\* $1 \*\//; }

    #Write out file
    if(defined $out) {print $out "$line\n";}
}
#Incase we get to the end of the file it should close the last file and mv the file to the right name.
if(defined $out) { close($out); `mv ${temp_location}/tmp.vams ${temp_location}/$filename`; }
close(FILE);
       
#######################################################################################
#Add contents of the splits files generate in ${temp_location}/*.vams into DB
####################################################################################### 
print "Adding modules in main netlist to DB\n";
foreach my $file (`ls ${temp_location}/*.vams`){
    chomp($file);
    if($file =~ /${temp_location}\/(.*)\.(.*)\.(.*)\.vams/) {
         $file =~ /${temp_location}\/(.*)\.(.*)\.(.*)\.vams/;
         $lib  = $1;
         $cell = $2;
         $view = $3;

         #Count indicates how many varaints of the lib:cell are there as more than one varaiant
         #muts be placed in its own unique lib
         my $count = 0;
         if(exists $libs_cnt{$lib}{$cell}) { $count = $libs_cnt{$lib}{$cell}{"count"} + 1; };
         $libs_cnt{$lib}{$cell}{"count"} = $count;
 
         $libs{$lib}{$cell}{".vams"}{$view} = { file   => File::Spec->rel2abs($file),
                                                count  => $count
                                         };
    } else {
         print "Filename of $file not in correct format of {lib}.{cell}.{view}.vams.\n";   
    }

}

#######################################################################################
#Add contents of textInputs into DB
####################################################################################### 
print "Adding modules in $textinputs to DB\n";
open(FILE, "<",$textinputs) or die "Failed to write to file $textinputs";
while(<FILE>){
    chomp;                                                        
    if($_ =~ m/^-amscompilefile /){        
        ($file) = $_ =~ /file:(.*?)[ \"]/; 
        ($lib)  = $_ =~ /lib:(.*?)[ \"]/;  
        ($cell) = $_ =~ /cell:(.*?)[ \"]/; 
        ($view) = $_ =~ /view:(.*?)[ \"]/; 

        #Some mappings that come out of the netlister
        $file =~ s/\${IC_INVOKE_DIR}/${virtuoso_path}/g;
        $file =~ s/\${AMS_CIC_HIER}/${virtuoso_root}/g;
        $file =~ s/\$(\w+)/$ENV{$1}/g;
        
        #Check there has not been a mapping error and some env is missed.
        if(!(-e $file)) { print "File $file not mapped correctly"; }

        #Get details of the file.
        my ($text_file, $text_path, $text_suffix) = fileparse($file, qr/\.[^.]*/); 
        
        my $count = 0;
        if(exists $libs_cnt{$lib}{$cell}) { $count = $libs_cnt{$lib}{$cell}{"count"} + 1; }
        $libs_cnt{$lib}{$cell}{"count"} = $count;        
        
        $libs{$lib}{$cell}{$text_suffix}{$view} = { file   => File::Spec->rel2abs($file),
                                                    count  => $count      
                                                  };
    }
    
}
close(FILE);

#######################################################################################
#Create cat'ed library files.
####################################################################################### 
print "Merging files into libraries\n";
`touch $outdir/filelist.f;`;
foreach my $lib ( sort keys %libs) {
    foreach my $cell ( sort keys %{$libs{$lib}} ) {
        foreach my $ext (sort keys %{$libs{$lib}{$cell}} ) {
            foreach my $view (sort keys %{$libs{$lib}{$cell}{$ext}} ) {
                
                my $libname = $lib;
		my $lib_file= "${libname}.common"; # Name of file for cells without explicity view differences
                
                if($libs{$lib}{$cell}{$ext}{$view}{count} > 0) { 
                    #Use the count and variant which is working. One sugguestion
                    #of using the view name is probably going to work and better as you 
                    #can't have 2 views of the same name for the same cells. Needs testing
                    $libname = "${libname}_variant_".($libs{$lib}{$cell}{$ext}{$view}{count});    

                    $lib_file = "${libname}";
                } 

                #Add lib name to the view the we know where the data should be pushed to.
                $libs{$lib}{$cell}{$ext}{$view}{"libname"} = "$libname";               
                
                #Create file for the output to go to.                                
                my $out_file = "$temp_location/merged/${lib_file}${ext}";
                                
                #Add to file that is <library name>.<ext>
                #Create file it not already there and added a new line top and bottom of the one cat'ed in
                if(!-e ${out_file}) {
                    $gen_files{$out_file} = ${libname};
                    #Create file 
                    `touch ${out_file}`;
                    `echo "\n"                                  >> ${out_file}`;
                }
                `echo "\n"                                  >> ${out_file}`;   
                `cat  $libs{$lib}{$cell}{$ext}{$view}{file} >> ${out_file}`;
                `echo "\n"                                  >> ${out_file}`;   

                #Create hash for lib.map
                $libmap_mapping{$libname}{"${netlist_path}/${lib_file}${ext}"} = ($libmap_mapping{$libname}{"${netlist_path}/${lib_file}${ext}"} || 0) + 1;
                
                if($libmap_mapping{$libname}{"${netlist_path}/${lib_file}${ext}"} == 1) { 
                    `touch $outdir/filelist.f; echo '${netlist_path}/${lib_file}${ext}' >> $outdir/filelist.f`;
                }
            }
        }
    }
}

#Add as footer to files.
print "Copying Merged files to $outdir\n";
foreach my $out_file (keys %gen_files) {   
    `cp $out_file $outdir`;
}

#######################################################################################
#Use DB to convert .amsbind.scs to Verilog-Configuration
####################################################################################### 
print "Creating Verilog Configuration file and filelist.f from $amsbind file\n";
my $first = 1;
my @ext_dig_cells;
my @ext_ana_cells;
open(FILE,   "<",$amsbind) or die "Failed to open $amsbind file";
open(CONFIG, ">","${outdir}/${verilog_config}") or die "Failed to write to file ${outdir}/${verilog_config}";
while(<FILE>){
    chomp;
    if($_ =~ m/^\s*config\s+designtop=\"(.*)\.(.*):(.*)\".*$/) {
        printf CONFIG "      design $1.$2;\n";        
        printf CONFIG "      default liblist $1 `ifdef XCELIUM worklib `else work `endif;\n";
    }
    #General mapping we have lib/cell/view to check it exists in DB
    elsif($_ =~ m/^\s*config\s+cell=\"(.*)\"\s+lib=\"(.*)\"\s+view=\"(.*?)\".*$/){
        #For $2 we need to align with the DB library name
        CELL_MAP: {
            foreach my $t (sort keys %{$libs{$2}{$1}}) {
                foreach my $tt (sort keys %{$libs{$2}{$1}{$t}}) {
                    if($tt eq $3) {
                        printf CONFIG "   cell     %-150s use %s.%s;\n", $1, $libs{$2}{$1}{$t}{$tt}{"libname"}, $1;
                        last CELL_MAP;
                    }
                }
            }
        }
    }
    #digitaltext has some corner cases where the file is part of the netlist like the cds_thrualias/cds_thru
    elsif($_ =~ m/^\s*config\s+cell=\"(.*)\"\s+view=\"digitaltext\".*$/){
        my $found = 0;
        #Need to search all libs for the cell and once found create a use statement.
        EXT_DIG: {
            foreach $lib ( sort keys %libs) {
                foreach  $cell ( sort keys %{$libs{$lib}})  {
                    foreach my $ext (sort keys %{$libs{$lib}{$cell}}) {
                        foreach $view (sort keys %{$libs{$lib}{$cell}{$ext}} ) {
                            if($cell eq $1) {
                                printf CONFIG "   cell     %-150s use %s.%s;\n", $1, $libs{$lib}{$cell}{$ext}{$view}{"libname"}, $1;
                                $found = 1;
                                last EXT_DIG;
                            }
                        }
                    }
                }
            }
            if(!$found) {
                #Cells is external to s claim it comes from another Verilog Configuration file.
                printf CONFIG "   cell     %-150s use %s; //digitaltext\n", $1, "work.sv_config__$1:config";
                push @ext_dig_cells, $1;
            }            
        }       
    } 
    #analogtext - Just need to list is in the file to say it comes from a model as a comment.
    elsif($_ =~ m/\s+config\s+cell=\"(.*)\"\s+view=\"analogtext\"/ ) {
        printf CONFIG "//   cell     %-150s liblist %s; //analogtext\n", $1, "ams_worklib";
    }      
    #Instance bindings
    elsif($_ =~ m/^\s*config\s+inst=\"(.*)\"\s+instMaster=\"(.*)\"\s+lib=\"(.*)\"\s+view=\"(.*)\"\s+parent=\"(.*?)\".*$/){
        if($first) { printf CONFIG "\n\n"; $first =0; }        
        #For $3 we need to align with the DB library name
        INST_MAP: {
            foreach my $t (sort keys %{$libs{$3}{$2}}) {
                foreach my $tt (sort keys %{$libs{$3}{$2}{$t}}) {
                    if($tt eq $4) {
                        printf CONFIG "   instance %-150s use %s.%s;\n", $1, $libs{$3}{$2}{$t}{$tt}{"libname"}, $2;
                        last INST_MAP;
                    }
                }
            }
        }
    }
    #BDU on instances to digitaltext or analogtext. Though the hierarchy needs to be all in BDU not WDU, so a bespoke
    #Verilog config might need to be created here that is instance specific
    elsif($_ =~ m/^\s*config\s+inst=\"(.*)\"\s+view=\"(.*)\"\s+parent=\"(.*?)\".*$/){
        my $inst = $1;
        my $view = $2;
        my $parent = $3;
        my $cell = "";
        if($view eq "digitaltext") {
             #not sure this is 100% correct for all use case.
             $inst =~ m/.*\.(.*)/;                   
             foreach (`grep '^\"$1\" ' $instbindtable`) {
                 chomp;
                 my @t = split(/\)\s*\(/, $_);                        
                 $t[1] =~ m/\"(.*)\"\s+\"(.*)\"\s+\"(.*)\"\s+\"(.*)\"\)/;
                 if($parent eq "$1.$2:$3") {
                     $t[0] =~ m/\(\(\(\"(.*)\"\s+\"(.*)\"\s+\"(.*)\"\s+\"(.*)\"/;
                     $cell = $2;
                     last;
                 }
             }
			 if($cell eq "") {
				printf CONFIG "   instance %-150s liblist work; //digitaltext\n", $inst;
			 } else {
             	printf CONFIG "   instance %-150s use %s; //digitaltext\n", $inst, "work.sv_config__${cell}:config";
             	#Could we end up with 2 or more instance bindings the same.
             	if(!grep( /^$cell$/, @ext_dig_cells )) { push @ext_dig_cells, $cell; }
			}
        } elsif($2 eq "analogtext") {
             #probably needs to be updated once i have a testcase. At the moment set them to work library
             printf CONFIG "//   instance %-150s liblist %s; //analogtext\n", $inst, "ams_worklib";
        } else {
             printf CONFIG "   //instance %-150s use %s; //BDU but has value $view not  analogtest/digitaltext\n", $inst, $view;
        }
    }
    
}
printf CONFIG "endconfig\n";

#For the ext_dig_cells/ext_ana_cells create Verilog Configs
foreach (@ext_dig_cells) {
  printf CONFIG "config sv_config__${_};\n";
  printf CONFIG "    design work.${_};\n";
  printf CONFIG "    default liblist work;\n";
  printf CONFIG "endconfig\n";
}

close(CONFIG);
close(FILE);
#Create filelist.f, filelist.snps.f and filelist.cdns.f to match cds2* script
`touch $outdir/filelist.f`;
`echo "\n\n// Verilog Configuration" >> $outdir/filelist.f`;
`echo '${netlist_path}/${verilog_config}' >> $outdir/filelist.f`;
`echo "-top  $top" >> $outdir/filelist.f`;

#######################################################################################
#Create lib.map file
####################################################################################### 
print "Creating Verilog Configuration lib.map file\n";
open(LIBMAP, ">","${outdir}/${lib_map_file}") or die "Failed to create ${outdir}/${lib_map_file}";
foreach my $t (sort keys %libmap_mapping) {
    foreach my $tt (sort keys  %{$libmap_mapping{$t}}) {
         printf LIBMAP "library %-40s \"%s\";\n", $t, $tt;
    }
}
close(LIBMAP);
`echo '-libmap  ${netlist_path}/${lib_map_file}' >> $outdir/filelist.f`;

#######################################################################################
#Create vcsAD.init file
#######################################################################################
if(-e $xrunargs) {
    print "Creating vcsAD.init file\n";
    my $spice_include_path = `grep "^\\s*\\-modelincdir" $xrunargs` || "";
    chomp($spice_include_path);
    $spice_include_path =~ s/\$\{IC_INVOKE_DIR\}\/://g;    #Will point to dfII folder
    $spice_include_path =~ s/^\s*-modelincdir\s*//g;     #Will be replaced in foreach loop
    #Could be : seperated and might need multiple -I commands
    my $xa_cmd_options='';
    foreach (split(":",$spice_include_path)) {  if($_ ne '') {$xa_cmd_options = $xa_cmd_options." -I $_";} }
    #Example vcsAD.init file to use
    open( VCSAD_FILE,">","$outdir/vcsAD.init")  or die "$outdir/vcsAD.init";
    print VCSAD_FILE "choose xa -spectre ${netlist_path}/spiceModels.scs -va,define SNPS ${xa_cmd_options} ;\n";
    close(VCSAD_FILE);
}

#######################################################################################
#Copy the globals file and short any globals to GND!
#######################################################################################
my @global_params;
if(-e "$temp_location/netlist/cds_globals.vams") {  
    my @global_nodes;
    my @global_grounds;
    my $ground_node = "";
    my $gnd_defined = 0;
    open(my $globals_file, "<", "$temp_location/netlist/cds_globals.vams");
    open(my $op_globals_file, ">","$outdir/cds_globals.vams");
    while(<$globals_file>) {
       #Deal with userDisciplines / wires
       #Delay with the fact we could get duplciates
       if($_ =~ m/^`include \"userDisciplines.vams\"/) {  print $op_globals_file "`include \"userDisciplines.vams\"\n"; }
       elsif ($_ =~ m/^(\s+)wire\s+(.*);$/) { if(!grep(/^${2}$/,@global_nodes) ) { print $op_globals_file "${1}electrical ${2};\n"; push (@global_nodes, "${2}"); }}
       elsif ($_ =~ m/endmodule/) { next;}
       elsif ($_ =~ m/^(\s+)ground\s+(.*);$/) { if(!grep(/^${2}$/,@global_grounds) ) { print $op_globals_file "${1}ground     ${2};\n"; push (@global_grounds, "${2}") ; if( ${2} =~ m/\\gnd! /) { $gnd_defined = 1; } }}
       else {
           #Fix indentation
           $_ =~ s/^\/\/ Global/   \/\/ Global/;
           $_ =~ s/^\/\/ Design/   \/\/ Design/;
 
           #Fix any unset dynamic parameters
           if( $_ =~ m/\"\*\* unset \*\*\"/) {
               print("Warning Dynamic Parameter with unset value : $_\n");
               $_ =~ s/\"\*\* unset \*\*\"/\/\* unset \*\/ 0/;
           }
 
           #Report any global parameters
           if($_ =~ m/^\s+dynamicparam\s+\S+\s+(\S+)\s+=/) {
               push (@global_params, "${1}");
           }
 
           #Change dynamicparam to paramter
           $_ =~ s/(^\s+)dynamicparam\s+/$1parameter /g;
           print $op_globals_file "$_";
       }
 
    }

    #Add \vdd! and \vss! if they are not already defined as Cadence use cds_globals.\vss! and cds_globals.\vss! as
    #the defaults for inherited connections on text views. Even if these are not used after the netset have been applied
    #the nets must exist in the design.
    print $op_globals_file "   logic \\vdd! ;\n" unless ((grep {'\vdd! '} @global_nodes) || (grep {'\vdd! '}  @global_grounds));
    print $op_globals_file "   logic \\vss! ;\n" unless ((grep {'\vss! '} @global_nodes) || (grep {'\vss! '}  @global_grounds));
 
    #Globals should never be used and if there are then it tends to indicate an issue in the setup. Only gnd! should be a
    #global
    my $count = 0;
    foreach my $node (@global_nodes) {
       if( !(grep {/^\Q$node\E$/} @global_grounds) ) {
           print $op_globals_file "   vsource #(.dc(0), .type(\"dc\")) vglobal_short_$count (${node}, \\gnd! );\n";
           $count = $count + 1;
       }
    }
    print $op_globals_file "\nendmodule\n";
    close($globals_file);
    close($op_globals_file);
 
    if (-e "${temp_location}/netlist/userDisciplines.vams") {
        system("cp  ${temp_location}/netlist/userDisciplines.vams ${outdir}/userDisciplines.vams");
    }
 
    #Print any global nodes out.
    print("Global Grounds                    : @global_grounds\n");
    print("Global Nodes (Shorted to ground)  : @global_nodes\n");
    print("Global Params                     : @global_params\n");
 
}

#######################################################################################
#Some other netlist files.
#######################################################################################
`echo '+incdir+${netlist_path}' >> $outdir/filelist.f`;

#Spice model 
if(-e "$temp_location/netlist/spiceModels.scs") {
    open(my $spicemodels,   "<", "${temp_location}/netlist/spiceModels.scs");
    open(my $op_spicemodels,">", "${path}spiceModels.scs");
    while(<$spicemodels>){
       chomp;
       #Map IC_INVOKE_DIR by mapping to the path to virtuoso.
       $_ =~ s/\$\{IC_INVOKE_DIR\}/\Q${virtuoso_path}\E/;
       #Fix WORKSPACE paths
       if(defined $ENV{WORKSPACE}) { $_ =~ s/\$ENV{WORKSPACE}/\$WORKSPACE/;}
       #remove amsd_subckt_bind statements
       $_ =~ s/ amsd_subckt_bind=yes//g;
       #Deal with spice/spectre/pspice text views
       #include "<some path>/<cell>/<view>/spectre.scs"
       if($_ =~ m/^\s*(?:pspice_)?include\s+\"(.*\/\w+\/\w+\/(spice\.spc|spectre\.scs|design\.pspice))\"(.*)$/) {
            my $line = $1;
            my $post_fix = $3;
            $line =~ m/.*\/(\w+)\/(\w+)\/(spice\.spc|spectre\.scs|design\.pspice)/;
            `cp -L $line  ${path}$1.$2.$3; chmod +w ${path}$1.$2.$3`;
            my $include = ($line =~ m/.*\.pspice$/) ? "pspice_include":"include";
            print $op_spicemodels "$include \"$1.$2.$3\"$post_fix\n";
        } else {
           print $op_spicemodels "$_\n";
        }
    }
    close($spicemodels);
    close($op_spicemodels);
}

#PureAnalog files just copy over.
if( -e "$temp_location/netlist/pureAnalogSrcfile.scs") {
     `cp $temp_location/netlist/pureAnalogSrcfile.scs  $outdir`;
     #Cadence's AMS shared the parameters in the cds_globals in the spectre engine as well. This is
     #done in the simulator. For Synopsys copy the parameters over to the pureAnalogSrcfile.scs file
     #and insert before the first include statement.
     foreach my $param (@global_params) {
         #`sed -i '1 i\\parameter $param = 0' $outdir/pureAnalogSrcfile.scs`;
         `perl -0777 -pi -e 's/^(simulator lang=spectre\\s*\$)/parameter $param = 0\\n\$1/g' $outdir/pureAnalogSrcfile.scs`;
     }
}
if( -e "$temp_location/netlist/pureAnalog.scs")        {
     `cp $temp_location/netlist/pureAnalog.scs         $outdir`;

}

#######################################################################################
#Copy Spectre Verilog-A files
#######################################################################################
if(-e "${temp_location}/netlist/ahdlIncludes"){
    my %ahdl_files;
    my $out_file;
    my $inc_file;
    #Fix the path
    system("perl -0777 -pi -e 's/\\\${IC_INVOKE_DIR}/\Q${virtuoso_path}\E/g' ${temp_location}/netlist/ahdlIncludes");
    open(my $IN,"<","${temp_location}/netlist/ahdlIncludes");
    open(my $OUT,">","${outdir}/ahdlIncludes");
    while(<$IN>) {
        chomp;
        $inc_file = $_;

        #Deal with includes for Verilog-A. Syntax is 'ahdl_include "file" [-master mapped_name]'
        #The -master allows a module defined in Verilog-A to be mapped to a different name in the Spectre netlist
        if($inc_file =~ m/^ahdl_include\s+\"(.*)\"(?:\s+-master\s+(.*))?$/) {
            #If $2 is defined then it is a mapped cell. E.g. the module name is mapped to a different module instance in the netlist
            #This way we can't merge them all into one file but need to be individual.
            if(defined $2)  { $out_file = "${filename}.$2.va"; }
            else            { $out_file = "${filename}.va";    }

            #Add to hash list to keep track of all the include files needed and the master name if
            #needed.
            $ahdl_files{$out_file} = (defined $2 ? $2:undef);

            system("cat $1 >> ${outdir}/${out_file}; echo \"\n\n\" >> ${outdir}/${out_file}");

        }
        #Deal with spice/spectre text views
        #include "<PATH TO CELL>/spiceText/spice.spc"
        #elsif($inc_file =~ m/^include\s+\"(.*)\"$/) {
        #  #could these just be included in the netlist with the simulate lang=* system?
        #  $out_file = "${filename}.${va_ext}";
        #}
        else { print $OUT "$inc_file\n"; }
    }
    close($IN);
    close($OUT);

    #If a Verilog-A file was generated then add the include line to the bottom of the ahdlIncludes file. This
    #needs to work with the -master option so we could have multiple include files for Verilog-A
    #Also fix the file path for dfii mode to use workspace.
    if((keys %ahdl_files) > 0) {
         system("echo \"\n//Verilog-A include files.\" >> ${outdir}/${filename}.va");
         foreach my $ahdl_file (keys %ahdl_files) {
            if(defined $ahdl_files{$ahdl_file}) { system("echo \"ahdl_include \\\"${ahdl_file}\\\" -master $ahdl_files{$ahdl_file}\" >> ${outdir}/ahdlIncludes"); }
            else                                { system("echo \"ahdl_include \\\"${ahdl_file}\\\"\" >> ${outdir}/ahdlIncludes"); }
         }
    }
}

   
#cds_alias is not part of AMS netlist even if used. Reported many times.
#To be correct is should be a SV file and the port defined inout interconnect.
open( CDS_ALIAS, ">","$outdir/cds_alias.v") or die "$outdir/cds_alias.v";
print CDS_ALIAS "module cds_alias(a,a);\n";
print CDS_ALIAS "  parameter width = 1;\n";
print CDS_ALIAS "  inout [width-1:0] a;\n";
print CDS_ALIAS "endmodule\n";
print CDS_ALIAS " \n";
close(CDS_ALIAS);

#Add files to filelist
`echo '${netlist_path}/cds_globals.vams' >> $outdir/filelist.f`;
`echo '-v ${netlist_path}/cds_alias.v'   >> $outdir/filelist.f`;
`echo '-top cds_globals'                 >> $outdir/filelist.f`;

#######################################################################################
#Copy log files over
####################################################################################### 
`cp ${netlist_location}/run.log ${outdir}/${log}`;

#######################################################################################
#print out info in DB for debug and Remove temp folder
#######################################################################################
print "Creating text files from internal Database for debug\n";
open(DB_DATA, ">","${outdir}/vcsams_netlist.db_data.txt") or die "${outdir}/vcsams_netlist.db_data.txt";
foreach my $lib ( sort keys %libs) {
    foreach my $cell ( sort keys %{$libs{$lib}})  {
        foreach my $ext (sort keys %{$libs{$lib}{$cell}}) {
            foreach my $view (sort keys %{$libs{$lib}{$cell}{$ext}} ) {
                printf DB_DATA "%-50s %-80s %-15s %-4s %-150s %-2s \"%s\"\n", $lib, $cell, $view, $ext, $libs{$lib}{$cell}{$ext}{$view}{file}, $libs{$lib}{$cell}{$ext}{$view}{count}, $libs{$lib}{$cell}{$ext}{$view}{"libname"};
            }
        }
    }
}
close(DB_DATA);
if(!(defined $debug)) { 
    print "Removing Temp location:      $temp_location\n";    `rm -rf $temp_location`;
    print "Removing Netlist location:   $netlist_location\n"; `rm -rf $netlist_location`;
}
print "Conversion Time   : ".(time()-$start_time)." Seconds\n";


#######################################################################################
# This function generates random strings of a given length 
#######################################################################################
sub generate_random_string
{
   # the length of the random string to generate      
	my $length_of_randomstring=shift;

   #Valid charactors int he random string
	my @chars=('a'..'z','A'..'Z','0'..'9','_');
	
	my $random_string;
	foreach (1..$length_of_randomstring) 
	{
		# rand @chars will generate a random 
		# number between 0 and scalar @chars
		$random_string.=$chars[rand @chars];
	}
	return $random_string;
}


__DATA__
 
=head1 NAME

Netlisting script for Verilog-AMS that takes run runams to create a UNL-AMS netlist which
is then processed to create an LRM complaint one using Verilog Configuration and Library
mapping files.


=head1 VERSION

1.00 - initial Release.

=head1 SYNOPSIS

ams_netlist.pl -lib <I<dfII_Library_Name>> -cell <I<dfII_Cell_Name>> -view <I<dfII_View_Name>> -outdir <I<output_folder>> [options]

=over 4

B<-lib>  Must be a valid the dfII library name where the cell resides.

B<-cell> Must be a valid the dfII cell name.

B<-view> Must be a valid the dfII view (HED) name.

B<-outdir> A folder that the resultant netlist is placed in. 

=back

=head1 OPTIONS

B<-cdslib>

=over 4

Location of the cds.lib to be used. If this is not defined it uses the search order.

=back

B<-verbose>

B<-debug>

B<-help>

=cut
