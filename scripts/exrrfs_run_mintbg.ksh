#!/bin/bash

#
#-----------------------------------------------------------------------
#
# Source the variable definitions file and the bash utility functions.
#
#-----------------------------------------------------------------------
#
. ${GLOBAL_VAR_DEFNS_FP}
. $USHdir/source_util_funcs.sh
#
#-----------------------------------------------------------------------
#
# Save current shell options (in a global array).  Then set new options
# for this script/function.
#
#-----------------------------------------------------------------------
#
{ save_shell_opts; set -u -x; } > /dev/null 2>&1
#
#-----------------------------------------------------------------------
#
# Get the full path to the file in which this script/function is located 
# (scrfunc_fp), the name of that file (scrfunc_fn), and the directory in
# which the file is located (scrfunc_dir).
#
#-----------------------------------------------------------------------
#
scrfunc_fp=$( readlink -f "${BASH_SOURCE[0]}" )
scrfunc_fn=$( basename "${scrfunc_fp}" )
scrfunc_dir=$( dirname "${scrfunc_fp}" )
#
#-----------------------------------------------------------------------
#
# Print message indicating entry into script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Entering script:  \"${scrfunc_fn}\"
In directory:     \"${scrfunc_dir}\"

This is the ex-script for the task that runs the post-processor (UPP) on
the output files corresponding to a specified forecast hour.
========================================================================"
case $MACHINE in

  "WCOSS2")
    module load wgrib2/2.0.8
    module list
    wgrib2=/apps/ops/prod/libs/intel/19.1.3.304/wgrib2/2.0.8_wmo/bin/wgrib2
    ;;

  "HERA")
    module load gnu/9.2.0
    module load wgrib2/3.1.0
    wgrib2=/apps/wgrib2/3.1.0/gnu/9.2.0_ncep/bin/wgrib2
    ;;

  "JET")
    module load intel/18.0.5.274
    module load wgrib2/2.0.8
    wgrib2=/apps/wgrib2/2.0.8/intel/18.0.5.274/bin/wgrib2
    ;;

  *)
    err_exit "\
Wgrib2 has not been specified for this machine:
  MACHINE = \"$MACHINE\"
  wgrib2 = `which wgrib2` "
    ;;

esac

#
#-----------------------------------------------------------------------
#
# Specify the set of valid argument names for this script/function.  
# Then process the arguments provided to this script/function (which 
# should consist of a set of name-value pairs of the form arg1="value1",
# etc).
#
#-----------------------------------------------------------------------
#
valid_args=( \
"cdate" \
"run_dir" \
"postprd_dir" \
"comout" \
"fhr_dir" \
"fhr" \
"tmmark" \
)
process_args valid_args "$@"
#
#-----------------------------------------------------------------------
#
# For debugging purposes, print out values of arguments passed to this
# script.  Note that these will be printed out only if VERBOSE is set to
# TRUE.
#
#-----------------------------------------------------------------------
#
print_input_args valid_args
#
#-----------------------------------------------------------------------
#
# A separate ${post_fhr} forecast hour variable is required for the post
# files, since they may or may not be three digits long, depending on the
# length of the forecast.
#
#-----------------------------------------------------------------------
#
DATA=$postprd_dir
export DATA=$postprd_dir
DATAmint=$DATA/mint_${fhr}
mkdir $DATAmint

cd $DATAmint

grids=hrrr
gridsarray=($grids)
num=${#gridsarray[@]}

if [[ $num -gt 10 ]] ; then
    echo "Only ten grid names may be specified.  User specified ${num}."
    exit
fi


#generate namelist input file, make sure that no grid in same domain is repeated twice
Tur=no; Tak=no; Tpr=no; Thi=no; Tgu=no
echo "&gridsinfo" > gridsinfo_input
echo "     grids=${num}" >> gridsinfo_input
nn=0
while [[ $nn -lt $num ]] ; do
    let nnp1="nn+1"
    dname=${gridsarray[$nn]}
    echo "     gridnames($nnp1)=${dname}," >> gridsinfo_input
    if [[ $dname = "cohreswexp" || $dname = "cohresext" || $dname = "cohres" || $dname = "rtma2p5" || $dname = "hrrr" ]] ; then
        if [[ $Tur = yes ]] ; then
            echo "MULTIPLE GRIDS FROM URMA2P5 DOMAIN!"
            exit
        else
            run="rtma3d"
            Tur=yes
        fi
    else
        echo "Domain name number ${nn} is invalid: $dname."
        exit
    fi
    #now find and run wgrib2 on all the relevant files for that grid
    CYCLE="${PDY}1800"
    CYCLEm1="${PDY}1700"
    CYCLE_STOP="${PDYm1}1800"

    while [[ $CYCLE -ge $CYCLE_STOP ]]; do

        YYYYMMDD=`echo $CYCLE | cut -c 1-8`
        HH=`echo $CYCLE | cut -c 9-10`
	YYYYMMDDm1=`echo $CYCLEm1 | cut -c 1-8`
	HHm1=`echo $CYCLEm1 | cut -c 9-10`

        #find proper name of ges and analysis files to run wgrib2 on based on run and domain name
        if [[ $run = "rtma3d" ]] ; then
            if [[ $dname == "hrrr" ]] ; then
                opsfile=${COMOUT_BASEDIR}/RTMA_NA.${YYYYMMDD}/${HH}/rtma.t${HH}z.prslev.f000.hrrr.grib2
                gesfile=${RRFS_GRIBDIR}/rrfs.${YYYYMMDDm1}/${HHm1}/rrfs.t${HHm1}z.prslev.f001.conus_3km.grib2
                if [[ ! -s $opsfile ]] ; then
                  if [[ ! -d ${COMOUT_BASEDIR}/RTMA_NA.${YYYYMMDD}/${HH} ]]; then
                    mkdir -p ${COMOUT_BASEDIR}/RTMA_NA.${YYYYMMDD}/${HH}
                  fi
	          cp $gesfile $opsfile
	        fi
	    fi
        fi
        #now use wgrib2 to pull ges/analysis from the file
        #use run in binary filename, regardless of grid
        if [[ -s $gesfile ]] ; then
            opnew=${run}_anl_valid${HH}.bin
            gesnew=${run}_ges_valid${HH}.bin
            if [[ -s $gesnew ]] ; then
                opnew=${run}_anl_valid${HH}_prevday.bin
                gesnew=${run}_ges_valid${HH}_prevday.bin
            fi
            wgrib2 $gesfile -match ":TMP:2 m above ground:" -ieee $gesnew
            wgrib2 $opsfile -match ":TMP:2 m above ground:" -ieee $opnew
        else
            echo "WARNING: ${RUN} file unavailable for ${CYCLE}!"
        fi

        #get template grid for 20Z

        if [ ${HH} -eq 20 ] ; then
            if [[ $run == "${run}" ]] ; then
                cp $gesfile gesfileus.grb2
            fi
        fi

        CYCLE=`$MDATE -60 $CYCLE`
    done
    let nn="$nn+1"
done
echo "/" >> gridsinfo_input
#in blend_input: 1=use bgs only, 2=use anls only, 3=use both
cat <<EOF > blend_input
&blendinput
bnum=3
/
EOF

#. prep_step

export FORT71=${run}.${PDYm1}.mint_diag_bg.dat
export FORT72=${run}.${PDYm1}.mint_diag_anl.dat

cp $FIX_MINMAXTRH/aktz.bin .
cp $FIX_MINMAXTRH/conusexttz.bin .
cp $FIX_MINMAXTRH/conustz.bin .
cp $FIX_MINMAXTRH/conustz_ndfdonly.bin .

export pgm=rrfs_mint.exe
#startmsg
${EXECdir}/rrfs_mint.exe  > stdout 2>&1 
export err=$?
#cat $pgmout

if [[ $Tur = yes ]]; then
if [ -s $DATAmint/mint_${run}_bg.bin ] ; then
    wgrib2 $DATAmint/gesfileus.grb2 -match ":TMP:" -grib_out $DATAmint/tempgribus.grb2
    wgrib2 $DATAmint/tempgribus.grb2 -import_ieee mint_${run}_bg.bin -set_date "${PDY}08" -set_var TMIN -set_ftime "12 hour fcst" -undefine_val 0 -grib_out $DATAmint/${run}.${PDYm1}.minT.grb2
    cp $DATAmint/mint_${run}_bg.bin $DATAmint/rtma3d.${PDYm1}.minT.bin
    cp $DATAmint/${run}.${PDYm1}.minT.grb2 $comout/rtma3d.minT.grib2
else
    echo "URMA2P5 background was not generated or copied properly!"
    exit
fi
fi


#-----------------------------------------------------------------------
#
# Print message indicating successful completion of script.
#
#-----------------------------------------------------------------------
#
print_info_msg "
========================================================================
Post-processing for forecast hour $fhr completed successfully.

Exiting script:  \"${scrfunc_fn}\"
In directory:    \"${scrfunc_dir}\"
========================================================================"
#
#-----------------------------------------------------------------------
#
# Restore the shell options saved at the beginning of this script/func-
# tion.
#
#-----------------------------------------------------------------------
#
{ restore_shell_opts; } > /dev/null 2>&1

