
#include "zck.h"

#include <cstdio>

using namespace std;
using namespace zck;


const char* TAB = "  ";
int g_next_id = 1;


string pretty_label(AST const* pNode) {
    auto const& t = pNode->token();
    string s = t.type_id_name();

    if ( (t.type_id() & Parser::TM_EMPTY) != Parser::TM_EMPTY ) {
        s += "\\n" + QUEX_NAME_TOKEN(lexeme_to_pretty_char)(t.get_text());
    }

    return s;
}


void walk_tree(AST const* pNode, int id = 0, bool has_label = false) {
    auto my_id = (id) ? id : g_next_id++;

    if (!has_label)
        cout << TAB << "node_" << my_id << "[label=\"" << pNode->token().type_id_name() << "\"]" << endl;

    for (auto&& pChild : pNode->children()) {
        auto child_id = g_next_id++;
        cout << TAB << "node_" << child_id << "[label=\"" << pChild->token().type_id_name() << "\"]" << endl;
        cout << TAB << "node_" << my_id << " -> " << "node_" << child_id << endl;
        walk_tree(pChild, child_id, true);
    }
}


int main(int argc, char const* argv[]) {
    try {
        Parser parser( (argc == 1) ? "example.zck" : argv[1] );
        cout << "digraph {" << endl << TAB << "rankdir=LR" << endl;
        walk_tree( parser.root() );
        cout << "}" << endl;
    }
    catch (std::exception& e) {
        cout << "Fatal: " << e.what() << endl;
        return 1;
    }

    return 0;
}
