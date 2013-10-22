# Naming convention for your master image
MASTER_IMAGE_NAME="MASTER-"

# Safety factor value
SAFETY_FACTOR=1.3

# enable threading to limit number of simontaneous copy of vmkfstools
ENABLE_THREADING=0

# number of simontaneous copy of vmkfstools (IO intensive)
MAX_THREAD=2

DEVEL_MODE=0
LC_EXECUTION_DIR=/tmp/linked_clones_run.$$

#functions
function loadBalanceOutput {
	LOCALTYPE=$1
	if [ "${LOCALTYPE}" == "loadbalance-write" ]; then
                counter=0
                while [ $counter -le $VMFS_MAX_COUNT ]
                do
                        counter=$(( ${counter} + 1 ))
                done
        fi

	if [ "${LOCALTYPE}" == "loadbalance-readwrite" ]; then
		local vm_cnt=$(( ${END_COUNT} - ${START_COUNT} + 1 ))
		local DISTRIBUTION=`expr "${vm_cnt}" / "${VMFS_MAX_COUNT}"`
		local counter=0
                while [ ${counter} -le ${VMFS_MAX_COUNT} ]
                do
                        counter=$(( ${counter} + 1 ))
                done

		local MASTER=0
		local mas_count=1
		local vm_count=${START_COUNT}
		local start_cnt=${START_COUNT}
		while [ ${MASTER} -le ${VMFS_LOAD} ]
		do
        		local NEXT=$(( ${MASTER} + 1 ))
        		mas_count=$(( ${mas_count} + 1 ))

        		if [ ! ${MASTER} -eq ${VMFS_LOAD} ]; then
                		for (( i = 1; i <= ${DISTRIBUTION}; i++ ))
                		do
		        		vm_cnt=$(( ${vm_cnt} - 1 ))
					vm_count=$(( 1 + ${vm_count} ))
	             		done
				local done=$[ ${vm_count} - 1]
				ARR_RANGE_START[${#ARR_RANGE_START[*]}]="${START_COUNT}"
				ARR_RANGE_END[${#ARR_RANGE_END[*]}]="${done}"
				START_COUNT=$(( ${done} + 1 ))
       			else
                		#if you're on the last array element, then you know you want to max out the remainder VMs
                		rem=$(( ${MAX} - ${vm_count} ))
				local start=${vm_count}

                		for (( j = 0; j <= ${rem}; j++ ))
                		do
                        		vm_cnt=$(( ${vm_cnt} - 1 ))
					vm_count=$(( 1 + ${vm_count} ))
                		done
				local done=$(( ${vm_count} - 1 ))
				ARR_RANGE_START[${#ARR_RANGE_START[*]}]="${start}"
				ARR_RANGE_END[${#ARR_RANGE_END[*]}]="${done}"
        		fi
        		MASTER=$(( ${MASTER} + 1 ))
		done
	fi
}

function getDiskRequirement {
	#golden vm vmdk size + (golden vm mem size * num of vms * safety factor + roundup value)
	#Round up is for compensation of the decimal calculation, so we round up by 1gb just to be safe
	ROUND_UP_G=1024
	G_MEM=`cat ${GOLDEN_VM_PATH}.vmx | grep memsize | awk '{print $3}' | sed 's/"//g'`
	G_VMDK_PATH=`echo ${GOLDEN_VM_PATH%/*}`
	G_SIZE_RET=`ls -lh ${G_VMDK_PATH} | grep flat | awk '{print $5}'`
	if [ -z ${G_SIZE_RET} ]; then
		echo "Could not locate the *-flat.vmdk for this Master VM" 1>&2
		exit 1
	fi
	echo ${G_SIZE_RET} | grep "G" > /dev/null 2>&1

	if [ $? -eq 0 ]; then
 		G_SIZE_GIG=`echo ${G_SIZE_RET} | sed 's/G//g'`
		G_SIZE=$(echo | awk '{ print "'"$G_SIZE_GIG"'"*1024}')
	else
		G_SIZE_MB=`echo ${G_SIZE_RET} | sed 's/M//g'`
		G_SIZE=$(echo | awk '{ print "'"$G_SIZE_MB"'"}')
	fi

	G_INITIAL=${G_SIZE}
	G_INPUT=$(echo | awk '{ print "'"$G_MEM"'"*"'"$SAFETY_FACTOR"'"*"'"$TOTAL_VM_CREATE"'"}')
	G_SIZE=$(echo | awk '{ print "'"$G_SIZE"'"*"'"$VMFS_MAX_COUNT"'"}')

	if [ "${TYPE}" == "loadbalance-write" ]; then
		DISK_REQUIRED=$(echo | awk '{ print "'"$ROUND_UP_G"'"+"'"$G_INPUT"'"}')
	else
		DISK_REQUIRED=$(echo | awk '{ print "'"$ROUND_UP_G"'"+"'"$G_SIZE"'"+"'"$G_INPUT"'"}')
	fi

	DISK_REQUIRED=$( printf %.0f $DISK_REQUIRED )
	if [ ${DISK_REQUIRED} -gt 1000 ]; then
		DISK_TOT=`expr ${DISK_REQUIRED} / 1024`
	else
		DISK_TOT=$(( ${DISK_REQUIRED} )) 
	fi
}

function createMasterImage {
	#creating mater image dir
	mkdir -p ${MASTER_PATH} > /dev/null 2>&1

	#duplicate .vmx config
	cp ${GOLDEN_VM_PATH}.vmx ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1

	VMDK_PATH=`grep scsi0:0.fileName ${GOLDEN_VM_PATH}.vmx | awk '{print $3}' | sed 's/"//g'`
	
	#update .vmx config to match master image
	sed -i 's/nvram = "'${GOLDEN_VM_NAME}.nvram'"/nvram = "'${MASTER_NAME}.nvram'"/' ${MASTER_PATH}/${MASTER_NAME}.vmx
	sed -i 's/extendedConfigFile = "'${GOLDEN_VM_NAME}.vmxf'"/extendedConfigFile = "'${MASTER_NAME}.vmxf'"/' ${MASTER_PATH}/${MASTER_NAME}.vmx
	sed -i 's/scsi0:0.fileName = "'${VMDK_PATH}'"/scsi0:0.fileName = "'${MASTER_NAME}.vmdk'"/' ${MASTER_PATH}/${MASTER_NAME}.vmx
	sed -i 's/displayName = "'${GOLDEN_VM_NAME}'"/displayName = "'${MASTER_NAME}'"/' ${MASTER_PATH}/${MASTER_NAME}.vmx
        sed -i '/ethernet0.generatedAddress/d' ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1
        sed -i '/uuid.location/d' ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1
        sed -i '/uuid.bios/d' ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1
        sed -i '/sched.swap.derivedName/d' ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1

	GOLDEN_VM_PATH_COPY=`echo ${GOLDEN_VM_PATH_COPY%/*}`
	GOLDEN_VM_PATH_COPY=${GOLDEN_VM_PATH_COPY}/${VMDK_PATH}
	vmkfstools -i ${GOLDEN_VM_PATH_COPY} ${MASTER_PATH}/${MASTER_NAME}.vmdk > /dev/null 2>&1

        vmware-cmd -s register ${MASTER_PATH}/${MASTER_NAME}.vmx > /dev/null 2>&1
        if [ $? -eq 1 ]; then
        	echo "Error trying to register new Virtual Machine - $FINAL_VM_NAME" 
        fi

	GOLDEN_VM_PATH=${MASTER_PATH}/${MASTER_NAME}
	GOLDEN_VM_NAME=${MASTER_NAME}
}

function createLinkedClone {
                mkdir -p ${STORAGE_PATH}/${FINAL_VM_NAME}

                cp ${GOLDEN_VM_PATH}.vmx ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx

		sed -i 's/displayName = "'${GOLDEN_VM_NAME}'"/displayName = "'${FINAL_VM_NAME}'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx 
		sed -i 's/extendedConfigFile = "'${GOLDEN_VM_NAME}.vmxf'"/extendedConfigFile = "'${FINAL_VM_NAME}.vmxf'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
		sed -i '/scsi0:0.fileName/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
		echo "scsi0:0.fileName = \"${GOLDEN_VM_PATH}.vmdk\"" >> ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
		sed -i 's/nvram = "'${GOLDEN_VM_NAME}.nvram'"/nvram = "'${FINAL_VM_NAME}.nvram'"/' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx
		
                sed -i '/ethernet0.generatedAddress/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1

                sed -i '/uuid.location/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
                sed -i '/uuid.bios/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
		sed -i '/sched.swap.derivedName/d' ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1

                vmware-cmd -s register ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx > /dev/null 2>&1
                if [ $? -eq 1 ]; then
                        echo "Error trying to register new Virtual Machine - $FINAL_VM_NAME"
                fi

                vmware-cmd ${STORAGE_PATH}/$FINAL_VM_NAME/$FINAL_VM_NAME.vmx createsnapshot Cloned ${FINAL_VM_NAME}_Cloned_from_${GOLDEN_VM_NAME} > /dev/null 2>&1
		echo "${GOLDEN_VM_NAME} ${STORAGE_PATH}/${FINAL_VM_NAME}/${FINAL_VM_NAME}.vmx" >> "${LC_CREATED_VMS}" 
}

function getProgress {
        WATCH_FILE=${LC_CREATED_VMS}
        EXPECTED_LINES=${TOTAL_VM_CREATE}
        while sleep 5;
        do
                REAL_LINES=$(wc -l < "${WATCH_FILE}")
                REAL_LINES=`echo ${REAL_LINES} | sed 's/^[ \t]*//;s/[ \t]*$//'`
                P_RATIO=$(( (${REAL_LINES} * 100 ) / ${EXPECTED_LINES} ))
                P_RATIO=${P_RATIO%%.*}
                tput hpa 0
                (( ${REAL_LINES} >= ${EXPECTED_LINES} )) && break
        done
}

function executeNormalandLBW {
	getProgress &
        while [ "${COUNT}" -le "${MAX}" ];
        do
			FINAL_VM_NAME="${VM_NAMING_CONVENTION}"

                #figure out STORAGE_PATH
                if [ "${TYPE}" == "nonlb" ]; then
                        STORAGE_PATH=`echo ${GOLDEN_VM%/*/*}`
                else
                        if [ $VMFS_CNT -eq $VMFS_LOAD ]; then
                                STORAGE_PATH="${VMFS_VOLUMES_PATH_ARR[$VMFS_CNT]}"
                                VMFS_CNT=0
                        else
                                STORAGE_PATH="${VMFS_VOLUMES_PATH_ARR[$VMFS_CNT]}"
                                VMFS_CNT=$(( ${VMFS_CNT} + 1 )) 
                        fi
                fi

		#creat linked clones
		createLinkedClone

                COUNT=$(( ${COUNT} + 1 ))
        done
}

function kickOffLinkCloning {
	local start_range=$((${ARR_RANGE_START[$MASTER_COUNT]}))
	local end_range=$((${ARR_RANGE_END[$MASTER_COUNT]}))
                createMasterImage
                for (( i = ${start_range}; i <= ${end_range}; i++ ))
                do
                        GOLDEN_VM_PATH=${VMFS_VOLUMES_PATH_ARR[${MASTER_COUNT}]}/${MASTER_IMAGE_NAME}${VM_NAMING_CONVENTION}${mas_num_count}/${MASTER_IMAGE_NAME}${VM_NAMING_CONVENTION}${mas_num_count}
                        FINAL_VM_NAME=${VM_NAMING_CONVENTION}${i}
                        STORAGE_PATH=${VMFS_VOLUMES_PATH_ARR[${MASTER_COUNT}]}

                        #call function
                        createLinkedClone
                        vm_cnt=$(( ${vm_cnt} - 1 ))
                done
}

function executeLBRW {
	local run=0
        local MASTER_COUNT=0
        local vm_cnt=$(( ${END_COUNT} - ${S_CNT} + 1 ))
        local mas_num_count=1
        local linkclone_count=${S_CNT}
        local DISTRIBUTION=`expr "${vm_cnt}" / "${VMFS_MAX_COUNT}"`
	local threadcount=0

	#get progress for linkclones only
	getProgress &

        while [ ${MASTER_COUNT} -le ${VMFS_LOAD} ]
	do
                local NEXT=$(( $MASTER_COUNT + 1 ))
	        MASTER_PATH=${VMFS_VOLUMES_PATH_ARR[${MASTER_COUNT}]}/${MASTER_IMAGE_NAME}${VM_NAMING_CONVENTION}${mas_num_count}
	        MASTER_NAME=${MASTER_IMAGE_NAME}${VM_NAMING_CONVENTION}${mas_num_count}

		#start thread process for vmkfstools copy + link-cloning
		kickOffLinkCloning &

		threadcount=$(( ${threadcount} + 1))
		if [[ ${threadcount} -eq ${MAX_THREAD} ]] && [[ ${ENABLE_THREADING} -eq 1 ]]; then
#			echo "Thread max of ${MAX_THREAD} has been execeeded, must wait for current processes to finish first ..."
			wait
			threadcount=0
		fi

		mas_num_count=$(( ${mas_num_count} + 1 ))
                MASTER_COUNT=$(( ${MASTER_COUNT} + 1 ))
        done
}

function validateUserInput {
	if ! echo ${GOLDEN_VM} | egrep -i '[0-9A-Za-z]+.vmx$' > /dev/null && [[ ! -f "${GOLDEN_VM}"  ]]; then
        	echo "Error: Golden VM Input is not valid" 1>&2
        	exit 1
	fi
	if [ "${DEVEL_MODE}" -eq 1 ]; then echo -e "\n############# SANITY CHECK START #############\n\nGolden VM .vmx file exists"; fi

        #check to verify Golden VM is offline before duplicating
        if ! vmware-cmd "${GOLDEN_VM}" getstate | awk '{print $3}' | tr A-Z a-z | grep "off" > /dev/null 2>&1; then
                echo "Master VM status is currently online or not registered." 1>&2
                exit 1
        fi
        if [ "${DEVEL_MODE}" -eq 1 ]; then echo "Golden VM is offline"; fi

	local mastervm_dir=$(dirname "${GOLDEN_VM}")
	if ls "${mastervm_dir}" | grep -E '(delta|-rdm.vmdk|-rdmp.vmdk)' > /dev/null 2>&1; then
		echo "Master VM contains either a Snapshot or Raw Device Mapping." 1>&2
		exit 1
	fi
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "Snapshots and RDMs were not found"; fi

	if ! grep "ethernet0.present = \"true\"" "${GOLDEN_VM}" > /dev/null 2>&1; then
		echo "Master VM does not contain valid eth0 vnic, script requires eth0 to be present." 1>&2
		exit 1
	fi	
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "eth0 found and is valid"; fi	

	vmdks=($(grep scsi "${GOLDEN_VM}" | grep fileName | awk -F "\"" '{print $2}'))
	if [ "${#vmdks[*]}" -gt 1 ]; then echo "Found more than 1 VMDK associated with the Master VM, script only supports a single VMDK." 1>&2; exit 1; fi
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "Single VMDK disk found"; fi

	if ! echo ${START_COUNT} | egrep '^[0-9]+$' > /dev/null; then
        	echo "Error: START value is not valid" 1>&2
        	exit 1
	fi
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "START parameter is valid"; fi

	if ! echo ${END_COUNT} | egrep '^[0-9]+$' > /dev/null; then
        	echo "Error: END value is not valid" 1>&2
	        exit 1
	fi
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "END parameter is valid"; fi

	#sanity check to verify your range is positive
        if [ "${START_COUNT}" -gt "${END_COUNT}" ]; then
                echo "Your Start Count can not be greater or equal to your End Count." 1>&2
                exit 1
        fi
#        if [ "${DEVEL_MODE}" -eq 1 ]; then echo "START and END range is valid"; fi

	#sanity check to make sure you're executing on ESX 3.x host or greater
	if [ ! -f /usr/bin/vmware ]; then
        	echo "This script is meant to be executed on VMware ESX 3.x or greater" 1>&2
	        exit 1
	else
		ESX_VER=$(vmware -v | awk '{print $4}')
		if [[ ! "${ESX_VER}" == "3.5.0" ]] && [[ ! "${ESX_VER}" == "3.0.3" ]] && [[ ! "${ESX_VER}" == "3.0.2" ]] && [[ ! "${ESX_VER}" == "3.0.1" ]] && [[ ! "${ESX_VER}" == "3.0.0" ]]; then
		        echo "Linked Clones script only supports ESX 3.x or greater" 1>&2
        		exit 1
		fi
	fi
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo "ESX Version valid (3.x+)"; fi

	#end of sanity check
#	if [ "${DEVEL_MODE}" -eq 1 ]; then echo -e "\n########### SANITY CHECK COMPLETE ############";exit; fi

	NUM_VMS=$(( ${END_COUNT} - ${START_COUNT} + 1 ))

	#working directory of current execution of linked clones
	mkdir -p ${LC_EXECUTION_DIR}
}

#DO NOT TOUCH INTERNAL VARIABLES
#set variables
GOLDEN_VM=$1
VM_NAMING_CONVENTION=$2
START_COUNT=$3
END_COUNT=$4
S_CNT=$START_COUNT

#sanity check on the # of args and validate data + set type of user case
case $# in 
	5) 
	   validateUserInput

	   TOTAL_VM_CREATE=$(( ${END_COUNT} - ${START_COUNT} + 1 ))

           if [ "$5" == "dw" ]; then
		TYPE=loadbalance-write
	   elif [ "$5" == "drw" ]; then
		TYPE=loadbalance-readwrite
	   else
 #               echo -e "\nParameter 5 should equal \"dw\" or \"drw\" if you're doing load-balancing\n"
                #printUsage
		rm -rf ${LC_EXECUTION_DIR}
                exit 1
           fi
	   #create a tmp file to hold the vmfs allowed paths
	   VMFS_PATH=${LC_EXECUTION_DIR}/vmfs_path.$$
	   VMFS_DS=${LC_EXECUTION_DIR}/vmfs_tmp.$$
	   cat /dev/null > "${VMFS_PATH}"
	   cat /dev/null > "${VMFS_DS}"

	   vmfs_counter=1
	   SELECT_ARR=""
	   IFS=$'\n' 
#           echo -e "#FREE SPACE\tDATASTORE(S)"
	   for i in `vdf -h -P | grep -E '^/vmfs/volumes/' | awk '{print $1 "\t" $4 "\t" $6}'`;
	   do
		free=`echo -e $i | awk '{print $2 "\t" $3}'`
	   	echo -e "${vmfs_counter})    ${free}"
		echo "${i}" | awk '{print $1 " " $3} ' >> "${VMFS_DS}" 
		vmfs_counter=$(( ${vmfs_counter} + 1 ))
           done
           #vmfs_counter=$(( ${vmfs_counter} + 1 ))
	   echo -e "${vmfs_counter})    Quit"
           unset IFS

#	   echo -e "\nPlease select datastore(s) to be used: (e.g. 1,2,3):"
	   IFS=,
	   read -a arr_selection
	   for selection in "${arr_selection[@]}";
	   do
           	VMFS_SEL=`echo ${selection} | sed 's/ //g'`
		#sanity check to ensure no other chars other than numbers are selected or if the user wants to quit
		case ${VMFS_SEL} in
			[a-zA-Z]*)
#				echo "ERROR: Invalid selection, please input a numerical value!" 1>&2
				rm -rf ${LC_EXECUTION_DIR}
				exit 1;
			${vmfs_counter}
#				echo "Exiting...." 1>&2
				rm -rf ${LC_EXECUTION_DIR}
                exit 0;;
		esac

		#validates the selection is between 1 and max # of lines
        if [[ ${VMFS_SEL} -ge 1 ]] && [[ ${VMFS_SEL} -le ${vmfs_counter} ]]; then
			grep "`sed -n ${VMFS_SEL}'p' ${VMFS_DS}`" "${VMFS_PATH}" > /dev/null 2>&1
			if [ $? -eq 1 ]; then
				sed -n ${VMFS_SEL}'p' ${VMFS_DS} >> "${VMFS_PATH}"
			fi
		else
#			echo "ERROR: Invalid selection..." 1>&2
			rm -rf ${LC_EXECUTION_DIR}
			exit 1
		fi	
	   done
	   unset IFS

	   #load vmfs_volumes paths into an array (UID path is used for validation check later)
	   VMFS_VOLUMES_PATH_ARR=( $(cat "${VMFS_PATH}" | awk '{print $2}') )
	   VMFS_MAX_COUNT=`echo ${#VMFS_VOLUMES_PATH_ARR[@]}`
	   VMFS_LOAD=$(( ${VMFS_MAX_COUNT} - 1 ))
	
	   #validate we have at least 1 VMFS volume selected, this is depercated due to the sanity checks above
	   if [ "${VMFS_MAX_COUNT}" -le 0 ]; then
		echo -e "\nYou must specify at least 1 datastore to store your VMs!" 1>&2
		rm -rf ${LC_EXECUTION_DIR}
		exit 1
           fi
	
	   #validate the combos for # of VMs & selected VMFS volumes
	   if [ "${VMFS_MAX_COUNT}" -gt "${NUM_VMS}" ]; then
	   	echo -e "\nYou must have more VMs to the number of datastore(s) if you to use this scheme!" 1>&2
        exit 1
	   fi

	   VMFS_CNT=0
	   ;;
	4) TYPE=nonlb
	   validateUserInput
           TOTAL_VM_CREATE=$(( ${END_COUNT} - ${START_COUNT} + 1 ));;
	*) #printUsage
	   rm -rf ${LC_EXECUTION_DIR}
	   exit 1;

esac 

#prep for duplication
GOLDEN_VM_PATH=`echo ${GOLDEN_VM%%.vmx*}`
GOLDEN_VM_NAME=`vmware-cmd ${GOLDEN_VM} getconfig DisplayName | awk '{print $3}'`
GOLDEN_VM_PATH_COPY=${GOLDEN_VM_PATH}
GOLDEN_VM_NAME_COPY=${GOLDEN_VM_NAME}

#special incremental counters
COUNT=${START_COUNT}
MAX=${END_COUNT}


	getDiskRequirement
	loadBalanceOutput ${TYPE}

##################
# Start of script

START_TIME=`date`
S_TIME=`date +%s`
LC_CREATED_VMS=${LC_EXECUTION_DIR}/newly_created_vms.$$
touch ${LC_CREATED_VMS}

if [ ! "${TYPE}" == "loadbalance-readwrite" ]; then
	################################################################
	# Standard Cloning to same VMFS Volume
	# Cloning distributed VMs Write across multiple VMFS Volumes
	################################################################
	executeNormalandLBW 
else
        ######################################################################
        # Cloning distributed VMs Read/Write(s) across multiple VMFS Volumes
        ######################################################################
	executeLBRW	
fi

sleep 10
wait
#echo -e "\n\nWaiting for Virtual Machine(s) to obtain their MAC addresses...\n"

##############################################

END_TIME=`date`
E_TIME=`date +%s`

#grab mac addresses of newly created VMs (file to populate dhcp static config)
PARENT_LIST=""
IFS=$'\n'
if [ -f ${LC_CREATED_VMS} ]; then
        for i in `cat ${LC_CREATED_VMS}`;
        do
                PARENT=$(echo ${i} | awk '{print $1}')
                CHILD=$(echo ${i} | awk '{print $2}')

		if ! echo "${PARENT_LIST}" | grep "${PARENT}" > /dev/null 2>&1; then
                	PARENT_LIST="${PARENT_LIST} ${PARENT}"
		fi
		PARENT_TMP=${LC_EXECUTION_DIR}/${PARENT}.tmp
		touch ${PARENT_TMP}
                if echo ${i} | grep "${PARENT}" > /dev/null 2>&1; then
                        VM_P=`echo ${CHILD##*/}`
                        VM_NAME=`echo ${VM_P%.vmx*}`
                        VM_MAC=`grep ethernet0.generatedAddress "${CHILD}" | awk '{print $3}' | sed 's/\"//g' | head -1 | sed 's/://g'`
                        while [ "${VM_MAC}" == "" ]
                        do
                                sleep 1
                                VM_MAC=`grep ethernet0.generatedAddress "${CHILD}" | awk '{print $3}' | sed 's/\"//g' | head -1 | sed 's/://g'`
                        done
                        echo "${VM_NAME}  ${VM_MAC}" >> ${PARENT_TMP}
                fi
        done
        unset IFS

	LC_WORKING_DIR="lcs_created_on-$(date +%F-%H%M%S)"
	mkdir -p ${LC_WORKING_DIR}
	#sort the list & remove tmp files
#	echo -e "Linked clones VM MAC addresses stored at:"
        for j in ${PARENT_LIST};
        do
                cat ${LC_EXECUTION_DIR}/${j}.tmp | sed 's/[[:digit:]]/ &/1' | sort -k2n | sed 's/ //1' > ${LC_WORKING_DIR}/${j}
#		echo -e "\t${LC_WORKING_DIR}/${j}"
		rm ${LC_EXECUTION_DIR}/${j}.tmp
        done
fi

DURATION=`echo $(( ${E_TIME} - ${S_TIME} ))`
rm -rf ${LC_EXECUTION_DIR}
echo "Successfully created Linked Clone"