readonly SUPPORTED_OMARCHY_VERSION=4
readonly REPOSITORY_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
readonly PACKAGE_CATALOG="$REPOSITORY_ROOT/packages.json"
readonly SKILL_MANIFEST="$REPOSITORY_ROOT/skills.json"

OMARCHY_DETECTED_VERSION=''
OMARCHY_DETECTED_MAJOR=''
OMARCHY_VERSION_MISMATCH=false

declare -A DEPENDENCY_VISIT_STATE=()
declare -a DEPENDENCY_ORDER=()
declare -a DEPENDENCY_STACK=()

wizard_uses_gum() {
	case ${DOTFILES_UI-auto} in
		gum) command -v gum >/dev/null 2>&1 ;;
		bash) return 1 ;;
		auto) [[ -t 0 ]] && command -v gum >/dev/null 2>&1 ;;
		*)
			printf 'Error: DOTFILES_UI must be auto, gum, or bash\n' >&2
			return 1
			;;
	esac
}

wizard_confirm() {
	local prompt=$1
	if wizard_uses_gum; then
		gum confirm "$prompt"
		return
	fi

	local answer
	printf '%s [y/N] ' "$prompt"
	read -r answer || answer=''
	[[ $answer == [yY] || $answer == [yY][eE][sS] ]]
}

visit_dependency() {
	local package=$1
	local state=${DEPENDENCY_VISIT_STATE[$package]-}
	if [[ $state == visiting ]]; then
		printf 'Error: package dependency cycle detected: %s -> %s\n' "${DEPENDENCY_STACK[*]}" "$package" >&2
		return 1
	fi
	if [[ $state == visited ]]; then
		return 0
	fi

	DEPENDENCY_VISIT_STATE[$package]=visiting
	DEPENDENCY_STACK+=("$package")
	local dependency
	while IFS= read -r dependency; do
		visit_dependency "$dependency" || return 1
	done < <(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .dependencies[]' "$PACKAGE_CATALOG")
	unset "DEPENDENCY_STACK[$((${#DEPENDENCY_STACK[@]} - 1))]"
	DEPENDENCY_VISIT_STATE[$package]=visited
	DEPENDENCY_ORDER+=("$package")
}

resolve_dependency_order() {
	DEPENDENCY_VISIT_STATE=()
	DEPENDENCY_ORDER=()
	DEPENDENCY_STACK=()
	local package
	for package in "$@"; do
		visit_dependency "$package" || return 1
	done
}

validate_catalog() {
	if ! jq -e 'type == "object" and (.packages | type == "array")' "$PACKAGE_CATALOG" >/dev/null 2>&1; then
		printf 'Error: invalid package catalog: %s\n' "$PACKAGE_CATALOG" >&2
		return 1
	fi

	local count index name path documentation
	count=$(jq '.packages | length' "$PACKAGE_CATALOG")
	for ((index = 0; index < count; index++)); do
		name=$(jq -r ".packages[$index].name // empty" "$PACKAGE_CATALOG")
		if [[ ! $name =~ ^[a-z][a-z0-9-]*$ ]]; then
			printf 'Error: invalid package name at index %d: package name must be lowercase\n' "$index" >&2
			return 1
		fi
		if [[ $(jq --arg name "$name" '[.packages[] | select(.name == $name)] | length' "$PACKAGE_CATALOG") -ne 1 ]]; then
			printf 'Error: duplicate package name: %s\n' "$name" >&2
			return 1
		fi

		path=$(jq -r ".packages[$index].path // empty" "$PACKAGE_CATALOG")
		if [[ $path != "config/$name" || ! -d $REPOSITORY_ROOT/$path ]]; then
			printf 'Error: invalid package path for %s: expected existing directory config/%s\n' "$name" "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].description | type == \"string\" and length > 0" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid description for package %s\n' "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].dependencies | type == \"array\" and all(.[]; type == \"string\" and test(\"^[a-z][a-z0-9-]*$\")) and (length == (unique | length))" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid dependencies for package %s\n' "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].prerequisites | type == \"array\" and all(.[]; type == \"string\" and length > 0)" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid prerequisites for package %s\n' "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].validators | type == \"array\" and all(.[]; type == \"string\" and length > 0)" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid validators for package %s\n' "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].documentation | . == null or (type == \"string\" and length > 0)" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid documentation for package %s\n' "$name" >&2
			return 1
		fi
		documentation=$(jq -r ".packages[$index].documentation // empty" "$PACKAGE_CATALOG")
		if [[ -n $documentation && ( $documentation == /* || $documentation == *../* || ! -f $REPOSITORY_ROOT/$documentation ) ]]; then
			printf 'Error: invalid documentation for package %s: referenced file does not exist\n' "$name" >&2
			return 1
		fi
		if ! jq -e ".packages[$index].cleanup | type == \"array\" and all(.[]; type == \"string\" and length > 0)" "$PACKAGE_CATALOG" >/dev/null; then
			printf 'Error: invalid cleanup metadata for package %s\n' "$name" >&2
			return 1
		fi
	done

	local dependency
	for ((index = 0; index < count; index++)); do
		name=$(jq -r ".packages[$index].name" "$PACKAGE_CATALOG")
		while IFS= read -r dependency; do
			if ! jq -e --arg dependency "$dependency" 'any(.packages[]; .name == $dependency)' "$PACKAGE_CATALOG" >/dev/null; then
				printf 'Error: package %s depends on missing package: %s\n' "$name" "$dependency" >&2
				return 1
			fi
		done < <(jq -r ".packages[$index].dependencies[]" "$PACKAGE_CATALOG")
	done

	local -a package_names=()
	mapfile -t package_names < <(jq -r '.packages[].name' "$PACKAGE_CATALOG")
	resolve_dependency_order "${package_names[@]}"
}

inspect_omarchy() {
	local warning_stream=${1-stdout}
	OMARCHY_DETECTED_VERSION=$(omarchy version)
	OMARCHY_DETECTED_MAJOR=''
	OMARCHY_VERSION_MISMATCH=false
	if [[ $OMARCHY_DETECTED_VERSION =~ (^|[^[:digit:]])([[:digit:]]+)([.]|$) ]]; then
		OMARCHY_DETECTED_MAJOR=${BASH_REMATCH[2]}
	fi
	printf 'Supported Omarchy: %s\n' "$SUPPORTED_OMARCHY_VERSION"
	printf 'Detected Omarchy: %s\n' "$OMARCHY_DETECTED_VERSION"
	if [[ $OMARCHY_DETECTED_MAJOR != "$SUPPORTED_OMARCHY_VERSION" ]]; then
		OMARCHY_VERSION_MISMATCH=true
		if [[ $warning_stream == stderr ]]; then
			printf 'Warning: detected Omarchy does not match supported version %s\n' "$SUPPORTED_OMARCHY_VERSION" >&2
		else
			printf 'Warning: detected Omarchy does not match supported version %s\n' "$SUPPORTED_OMARCHY_VERSION"
		fi
	fi
}

inspect_environment() {
	validate_catalog
	inspect_omarchy stdout
}
validator_executables_available() {
	local package validator executable missing=false
	for package in "$@"; do
		while IFS= read -r validator; do
			# Validator strings are not evaluated here: the supported preflight contract is that
			# the first whitespace-delimited shell word is the executable resolved by command -v.
			read -r executable _ <<<"$validator"
			if [[ -z $executable ]] || ! command -v "$executable" >/dev/null 2>&1; then
				printf 'Missing validator executable for %s: %s\n' "$package" "$validator" >&2
				missing=true
			fi
		done < <(jq -r --arg package "$package" '.packages[] | select(.name == $package) | .validators[]' "$PACKAGE_CATALOG")
	done
	[[ $missing == false ]]
}

phase_error() {
	local phase=$1
	local package=$2
	local recovery=$3
	printf 'Error: %s phase failed for package %s.\n' "$phase" "$package" >&2
	printf 'Recovery: %s\n' "$recovery" >&2
	return 1
}

path_type() {
	local path=$1
	if [[ -f $path && ! -L $path ]]; then
		printf 'regular file'
	elif [[ -d $path && ! -L $path ]]; then
		printf 'directory'
	elif [[ -L $path ]]; then
		printf 'symbolic link'
	else
		printf 'special file'
	fi
}
