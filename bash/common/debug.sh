# Track source nesting depth for indentation
_n2_source_depth=${_n2_source_depth:-0}

__n2_source() {
    local path
    path="$1"

    if [ "${N2_TRACE_SOURCE:-no}" = yes ]; then
        local _n2_indent=""
        local _n2_d=0
        while [ "$_n2_d" -lt "$_n2_source_depth" ]; do
            _n2_indent="${_n2_indent}  "
            _n2_d=$((_n2_d + 1))
        done
        echo "[n2:trace] ${_n2_indent}source $path" >&2
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

    # Increment depth for nested sources
    _n2_source_depth=$((_n2_source_depth + 1))

    source "$path"

    # Decrement depth after sourcing
    _n2_source_depth=$((_n2_source_depth - 1))

    # Log value changes for tracked variables (at same indent as source line)
    if [ -n "${N2_TRACE_VARS:-}" ]; then
        local _n2_var_indent=""
        local _n2_vd=0
        while [ "$_n2_vd" -lt "$_n2_source_depth" ]; do
            _n2_var_indent="${_n2_var_indent}  "
            _n2_vd=$((_n2_vd + 1))
        done
        _n2_i=0
        while [ "$_n2_i" -lt "${#_n2_var_names[@]}" ]; do
            _n2_var="${_n2_var_names[$_n2_i]}"
            _n2_old="${_n2_var_oldvals[$_n2_i]}"
            eval "_n2_new=\"\${${_n2_var}-__N2_UNSET__}\""
            if [ "$_n2_old" != "$_n2_new" ]; then
                if [ "$_n2_old" = "__N2_UNSET__" ]; then
                    echo "[n2:trace] ${_n2_var_indent}${_n2_var}: (unset) -> ${_n2_new}" >&2
                else
                    echo "[n2:trace] ${_n2_var_indent}${_n2_var}: ${_n2_old} -> ${_n2_new}" >&2
                fi
            fi
            _n2_i=$((_n2_i + 1))
        done
    fi
}
