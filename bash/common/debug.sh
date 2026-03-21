__n2_source() {
    local path
    path="$1"

    if [ "${N2_TRACE_SOURCE:-no}" = yes ]; then
        echo "[n2:trace] source $path" >&2
    fi

    # Capture pre-source values for tracked variables (bash 3.2+ compat: no assoc arrays)
    local _n2_var _n2_old _n2_new _n2_i IFS
    local _n2_var_names _n2_var_oldvals
    _n2_var_names=()
    _n2_var_oldvals=()
    if [ -n "${N2_TRACE_VARS:-}" ]; then
        IFS=' '
        for _n2_var in ${N2_TRACE_VARS//,/ }; do
            _n2_var_names+=("$_n2_var")
            eval "_n2_old=\"\${${_n2_var}-__N2_UNSET__}\""
            _n2_var_oldvals+=("$_n2_old")
        done
    fi

    source "$path"

    # Log value changes for tracked variables
    if [ -n "${N2_TRACE_VARS:-}" ]; then
        _n2_i=0
        while [ "$_n2_i" -lt "${#_n2_var_names[@]}" ]; do
            _n2_var="${_n2_var_names[$_n2_i]}"
            _n2_old="${_n2_var_oldvals[$_n2_i]}"
            eval "_n2_new=\"\${${_n2_var}-__N2_UNSET__}\""
            if [ "$_n2_old" != "$_n2_new" ]; then
                if [ "$_n2_old" = "__N2_UNSET__" ]; then
                    echo "[n2:trace] ${_n2_var}: (unset) -> ${_n2_new}" >&2
                else
                    echo "[n2:trace] ${_n2_var}: ${_n2_old} -> ${_n2_new}" >&2
                fi
            fi
            _n2_i=$((_n2_i + 1))
        done
    fi
}
