#!/bin/bash

IMAGE="etcd-browser" # Built image name
name="${IMAGE}"      # Docker instance name (used to configure then re-run)
port=""              # Web interface port
etcdport=""          # ETCD daemon port
host=""              # ETCD remote host
address=""           # Resolved IP or hostname
certstyle="auto"     # How to find certificates
certfile=""          # Client cert crt file
keyfile=""           # Client cert key file
cafile=""            # CA file
resolve=0            # Lookup host IP before starting container (if not resolvable within it)
keep=0               # Keep the container (don't use docker --rm)
debug=0              # To enable dry-run (just print docker command)
foreground=0         # Run in background
interactive=0        # Attach console
settings=.etcd-browserrc
exists=0
default_port=8000
default_address=localhost
default_etcdport=4001

prog="${0//*\/}"

function usage()
{
  {
    cat <<-EOF
	Usage:  ${prog} <options>
	Runs etcd-browser by Ryan Henszey
	  (see https://github.com/henszey/etcd-browser)
	
	Options:
	  [-h|-help|--help]
	  [-d|-debug|--debug]
	  [-i|-interactive|--interactive]  # Attach a console and run in foreground
	  [-fg|-foreground|--foreground]   # Run in foreground
	  [-r|-resolve|--resolve]          # resolve host before configuring container
	  [-k|-keep|--keep]                # keep configured image afterwards)
	  [-stop|--stop]                   # stop a running container
	  [-reset|--reset]                 # Delete the saved settings
	  [--rm]                           # don't keep configured image afterwards)
	  [--host=<host>]                  # set etcd host
	  [--name=<instance name>]         # set the docker container name. also enables -keep
	  [--image=<image name>]           # the docker build image name)
	  [--port=<number>]                # the web interface port (default: ${port:-${default_port}})
	  [--ca=<ca file>]                 # (default:${cafile})
	  [--cert=<client cert file>]      # (default:${certfile})
	  [--key=<client key file>]        # (default:${keyfile})
	  [--etcd=<etcd daemon port>]      # (default:${etcdport:-${default_etcdport}})
	  [--user=<auth username>]         # (default:${authuser})
	  [--pass=<auth password>]
	
	Config file:
	  Settings from each run are saved to / loaded from '~/${settings}' unless a container name was specified.
	  To delete old settings, delete that file.
	  If an image name is specified, the container will be kept and can be restarted with a simple command: ${prog} --name=<name>
	  or stopped with ${prog} --name=<name> -stop
	Example usage:
	
	  Configure etcd-browser as a container named etcd-local, then stop/restart it.
	    ${prog} --host=localhost --name=etcd-browser-local     # configure and start
	    ${prog} local -stop                                    # stop running container
	    ${prog} local                                          # restart saved image
	  Configure and run transient containers with different settings saved in ~/${settings}
	    ${prog} --host=etcd.demo 
	    ${prog} -stop
	    ${prog} --host=localhost
	    ${prog} -stop
	  Configure and save certificate settings, reusing them the next time, changing the web port:
	    ${prog} --ca=<file> --cert=<file> --key=<file> 
	    ${prog} -stop
	    ${prog} --port=8080
	EOF

    if [[ -f "${settings}" ]]
    then
      echo "Saved settings (for interactive use):"
      sed "s/^/  /" < "${settings}"
      echo ""
    fi

    check_container

    if (( exists ))
    then
      echo "Defaults:"
      echo "  Existing container ${name}" 
      echo "  With settings:"
      docker inspect --type=container --format='{{ range .Config.Env}}{{println .}}{{end}}' "${name}" | sed 's/^/    /'
    else
      cat <<-EOF
	Defaults:
	  provides web interface on port ${port:-${default_port}}
	  to view etcd host ${address:-${default_address}}:${etcdport:-${default_etcdport}}
	EOF

      if [[ "${certstyle}" != "none" ]]
      then
        echo "Certificate locations default to ${certstyle} on this system:"
      fi

      cat <<-EOF
	  CA file ${cafile}
	  Client cert file ${certfile}
	  Client key file ${keyfile}
	EOF
    fi
  } 1>&2
}

function err()
{
  echo "ERROR: ${*}" 1>&2
}

function inf()
{
  echo "INFO: ${*}" 1>&2
}

function check_file()
{
  local f="${1}"
  
  if [[ -n "${f}" && ! -f "${f}" ]]
  then
    err "File '${f}' does not exist"
    exit 1
  fi
}

function check_container()
{
  if docker inspect --type=container "${name}" > /dev/null 2> /dev/null
  then
    exists=1
  else
    exists=0
  fi
}

function lookup_host()
{
  local h="${host}"

  if [[ -z "${h}" ]]
  then
    echo "localhost"
  elif (( resolve ))
  then
    local ip=$(getent ahosts "${h}" | grep STREAM | head -n1 | awk '{print $1}')

    if [[ -z "${ip}" ]]
    then
      ip=$(host "${h}" | egrep 'has address' | awk '{print $4}' | head -n1)
      local ip_regex="^([0-9]{1,3}[.]){3}[.][0-9]{1,3})"
      if ! [[ "${ip}" =~ ${ip_regex} ]]
      then
        echo "WARN: could not look up host '${h}'." 1>&2
        echo "${h}"
        return 1
      fi
    fi
    echo "${ip}"
  else
    echo "${h}"
  fi
}

function run_cmd()
{
  echo "Run: " "${@}" 1>&2

  if (( debug ))
  then
    inf "Debug mode enabled - will not execute"
    return 0 
  fi

  if (( foreground ))
  then
    "${@}" 
  else
    "${@}" &
  fi
}

function run()
{
  local interactive_flags=()

 if (( interactive ))
  then
    inf "Running in foreground" 
    interactive_flags=(-t -i)
  else
    inf "Running as daemon."
  fi

  local vars=()

  check_container

  if (( exists ))
  then
    run_cmd docker start "${interactive_flags[@]}" "${name}"
  else

    check_file "${cafile}"
    check_file "${certfile}"
    check_file "${keyfile}"

    [[ -n "${address}"  ]] || address=$(lookup_host)
    (( keep ))             || vars+=( --rm ) 
    (( keep ))             || ((save++)) # Save settings only if not keeping an image. ie settings are saved for interactive use only
    [[ -n "${address}"  ]] && vars+=( --env ETCD_HOST="${address}" )
    [[ -n "${port}"     ]] && vars+=( --env SERVER_PORT="${port}" -p "0.0.0.0:${port}:${port}" )
    [[ -n "${certfile}" ]] && vars+=( --env ETCDCTL_CERT_FILE=/client.crt -v "${certfile}:/client.crt" )
    [[ -n "${keyfile}"  ]] && vars+=( --env ETCDCTL_KEY_FILE=/client.key  -v "${keyfile}:/client.key" )
    [[ -n "${cafile}"   ]] && vars+=( --env ETCDCTL_CA_FILE=/ca.crt       -v "${cafile}:/ca.crt" )
    [[ -n "${etcdport}" ]] && vars+=( --env ETCD_PORT="${etcdport}" )
    [[ -n "${authuser}" ]] && vars+=( --env AUTH_USER="${authuser}" )
    [[ -n "${authpass}" ]] && vars+=( --env AUTH_PASS="${authpass}" )

    # Save settings to config file only if:
    #  1. in home directory, 
    #  2. options were explicitly set
    #  3. keep flag is not set (not keeping an image) - saved options are for the transient container use 
    if [[ "${save}" -ge 3 ]] 
    then
      save_defaults
    fi

    run_cmd docker run --name "${name}" "${vars[@]}" "${interactive_flags[@]}" "${IMAGE}" 
  fi

}

function auto_cert_search()
{
  # Openshift origin support, only invoked if settings haven't been customised
  if [[ -d "/etc/origin/master" ]]
  then
    certs="/etc/origin/master"
    certstyle="openshift-origin"
  fi
}

function find_certs()
{
  if [[ "${certstyle}" == "auto" ]]
  then
    auto_cert_search
  fi

  case "${certstyle}" in
    openshift-origin)
     certfile="${certs}/master.etcd-client.crt"
     keyfile="${certs}/master.etcd-client.key"
     cafile="${certs}/ca.crt"
     ;;
  esac
}

function setup_defaults()
{
  if [[ -f "${settings}" ]]
  then
    echo "INFO: Loading settings from $(readlink -f "${settings}")"

    source "${settings}"

  else
    find_certs
  fi

  check_container
 
  if ! (( exists ))
  then
    [[ -n "${address}" ]] || address=$(lookup_host)
  fi
}

function save_defaults()
{
  inf "Saving settings to '${settings}"
  cat > "${settings}" <<-EOF
	IMAGE="${IMAGE}"
	certfile="${certfile}"
	keyfile="${keyfile}"
	cafile="${cafile}"
	port="${port}"
	etcdport="${etcdport}"
	host="${host}"
	authuser="${authuser}"
	EOF
}

function set_name()
{
  name="${1}"
  keep=1
}

function main()
{

  local arg=""

  # Handle usage request first without showing any info about loading settings file
  # Otherwise, defaults will be loaded below and an informative message printed.
  for arg in "${@}" 
  do
    case "${arg}" in
      -h|-help|--help)
        setup_defaults 2> /dev/null
        usage
        exit 0
        ;;
    esac
  done

  # This counter calculates when it is appropriate to save the settings file
  local save=0

  if cd 
  then
    setup_defaults
    # If we were able to enter the home dir, then it's OK to save the settings
    ((save++))
  fi

  local -a saved_options=()
  for arg in "${@}"
  do
    case "${arg}" in
    -i|-interactive|--interactive)
      interactive=1
      foreground=1
      ;;
    -fg|-foreground|--foreground)
      foreground=1
      ;;
    -d|-debug|--debug)
      debug=1
      ;;
    --rm)
      keep=0
      ;;
    -k|-keep|--keep)
      keep=1
      ;;
    --name=*)
      set_name "${arg#--name=}"
      ;;
    [a-zA-Z0-9]*)
      set_name "${IMAGE}-${arg}"
      inf "Using arg '${arg}' as container name suffix - full name is ${name}" 
      ;;
    *) 
      saved_options+=("${arg}")
      ;;
    esac
  done

  check_container

  # Next handle args for simple action modes which do something and then exit
  # that aren't setting variables, but need to run after an image name has been possibly been set
  for arg in "${saved_options[@]}"
  do

    case "${arg}" in
      -stop|--stop)
        foreground=1
        run_cmd docker stop "${name}"
        exit ${?}
        ;;
      -reset|--reset)
        inf "Deleting settings in ${settings}"
        (( save )) && rm "${settings}"
        exit 0
        ;;
    esac
  done

  for arg in "${saved_options[@]}"
  do
      
    if (( exists ))
    then
      err "Container ${name} exists or is running but image option ${arg} is being customised."
      err "You should remove the old container first with "
      err "  ${0} -stop --name=${name}   (for transient containers)"
      err "or "
      err "  docker stop ${name} ; docker rm ${name}           (for persistent containers)"
      err "or else specify a new name with --name=<newname>" 
      return 1
    fi
    
    case "${arg}" in
    -r|-resolve|--resolve)
      resolve=1
      ;;
    --image=*)
      IMAGE="${arg#--image=}"
      ;;
    --user=*)
      authuser="${arg#--user=}"
      ;;
    --pass=*)
      authpass="${arg#--pass=}"
      ;;
    --port=*)
      port="${arg#--port=}"
      ;;
    --cert=*)
      certfile="${arg#--cert=}"
      ;;
    --key=*)
      keyfile="${arg#--key=}"
      ;;
    --ca=*)
      cafile="${arg#--ca=}"
      ;;
    --etcd=*)
      etcdport="${arg#--etcd=}"
      ;;
    --host=*)
      host="${arg#--host=}"
      address=""
      ;;
    *)
      err "Unrecognised option: '${arg}'"
      usage
      exit 1
      ;;
    esac
    shift
  done

  # Increment save flag to indicate that some save-able options were modified
  (( ${#saved_options[@]} )) && ((save++))

  run
}

main "${@}"
