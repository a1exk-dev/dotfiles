#include <string_view>

#ifndef INPUT_LANGUAGES_BUILD_ID
#error INPUT_LANGUAGES_BUILD_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_SOURCE_ID
#error INPUT_LANGUAGES_SOURCE_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_COMPILER_ID
#error INPUT_LANGUAGES_COMPILER_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_COMPATIBILITY_ID
#error INPUT_LANGUAGES_COMPATIBILITY_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_INTEGRATION_ID
#error INPUT_LANGUAGES_INTEGRATION_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_PROTOCOL_ID
#error INPUT_LANGUAGES_PROTOCOL_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_CONTROLLER_ID
#error INPUT_LANGUAGES_CONTROLLER_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_HEALTH_ID
#error INPUT_LANGUAGES_HEALTH_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_UNIT_ID
#error INPUT_LANGUAGES_UNIT_ID must be defined
#endif
#ifndef INPUT_LANGUAGES_ARTIFACT_ROLE
#error INPUT_LANGUAGES_ARTIFACT_ROLE must be defined
#endif

namespace {
[[gnu::used, gnu::section(".input_languages_integration")]] const char INTEGRATION_ARTIFACT_IDENTITY[] =
	"version=1\n"
	"role=" INPUT_LANGUAGES_ARTIFACT_ROLE "\n"
	"integration=" INPUT_LANGUAGES_INTEGRATION_ID "\n"
	"build_id=" INPUT_LANGUAGES_BUILD_ID "\n"
	"source_id=" INPUT_LANGUAGES_SOURCE_ID "\n"
	"compiler=" INPUT_LANGUAGES_COMPILER_ID "\n"
	"compatibility=" INPUT_LANGUAGES_COMPATIBILITY_ID "\n"
	"protocol=" INPUT_LANGUAGES_PROTOCOL_ID "\n"
	"controller=" INPUT_LANGUAGES_CONTROLLER_ID "\n"
	"health=" INPUT_LANGUAGES_HEALTH_ID "\n"
	"unit=" INPUT_LANGUAGES_UNIT_ID "\n";
}
