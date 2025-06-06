#!/bin/bash

source /usr/local/bin/_liferay_bundle_common.sh
source /usr/local/bin/_liferay_common.sh

function main {
	echo "[LIFERAY] To SSH into this container, run: \"docker exec -it ${HOSTNAME} /bin/bash\"."
	echo ""

	if [[ "${DOCKER_TCMALLOC_ENABLED}" == "true" ]]
	then
		LD_PRELOAD="/usr/lib/x86_64-linux-gnu/libtcmalloc.so.4:${LD_PRELOAD}"

		export LD_PRELOAD

		echo -e "\nexport LD_PRELOAD=\"${LD_PRELOAD}\"" >> ~/.bashrc
	fi

	if [ -d /etc/liferay/mount ]
	then
		LIFERAY_MOUNT_DIR=/etc/liferay/mount
	else
		LIFERAY_MOUNT_DIR=/mnt/liferay
	fi

	export LIFERAY_MOUNT_DIR

	if [[ "${LIFERAY_CONTAINER_STARTUP_LOCK_ENABLED}" == "true" ]]
	then
		if [[ "${LIFERAY_CONTAINER_STATUS_ENABLED}" != "true" ]]
		then
			echo "Container status needs to be enabled with LIFERAY_CONTAINER_STATUS_ENABLED to enable startup lock."

			exit 1
		fi

		update_container_status acquiring-startup-lock

		/usr/local/bin/startup_lock.sh
	fi

	start_monitor_liferay_lifecycle

	start_interval_thread_dump &

	update_container_status pre-configure-scripts

	execute_scripts /usr/local/liferay/scripts/pre-configure

	. set_java_version.sh

	update_container_status configure

	. configure_liferay.sh

	if [ "${?}" -eq "${LIFERAY_COMMON_EXIT_CODE_BAD}" ]
	then
		echo "[LIFERAY] Unable to configure Liferay."
		echo ""

		exit "${LIFERAY_COMMON_EXIT_CODE_BAD}"
	fi

	update_container_status pre-startup-scripts

	execute_scripts /usr/local/liferay/scripts/pre-startup

	update_container_status liferay-start

	start_liferay

	update_container_status post-shutdown

	execute_scripts /usr/local/liferay/scripts/post-shutdown

}

function start_liferay {
	set +e

	start_liferay.sh &

	START_LIFERAY_PID=$!

	echo "${START_LIFERAY_PID}" > "${LIFERAY_PID}"

	wait ${START_LIFERAY_PID}
}

function start_interval_thread_dump {
	if [ ! -n "${LIFERAY_DOCKER_THREAD_DUMP_INTERVAL_FILE}" ]
	then
		return
	fi

	while true
	do
		if [ -s "${LIFERAY_DOCKER_THREAD_DUMP_INTERVAL_FILE}" ]
		then
			local sleep=$(cat "${LIFERAY_DOCKER_THREAD_DUMP_INTERVAL_FILE}")

			if ! [ "${sleep}" -gt 3 ] &>/dev/null
			then
				sleep=3
			fi

			/usr/local/bin/generate_thread_dump.sh -n 1 -s "${sleep}"
		else
			sleep 60
		fi
	done
}

function start_monitor_liferay_lifecycle {
	if [[ "${LIFERAY_CONTAINER_STATUS_ENABLED}" == "true" ]]
	then
		/usr/local/bin/monitor_liferay_lifecycle.sh &
	fi
}

main