
#include <example/magic.hpp>

#include <iostream>

signed
main() {
	std::cout
		<< "The magic is "
		<< Example::get_magical_number()
		<< '\n'
	; std::cout.flush();
	return 0;
}
