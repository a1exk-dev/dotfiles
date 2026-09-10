#pragma once

#include "fcitx-controller.hpp"

#include <ostream>

namespace InputLanguages::Fcitx {

int runControllerCommand(int argc, char** argv, ControllerTransport& transport, std::ostream& output, std::ostream& error);

}
