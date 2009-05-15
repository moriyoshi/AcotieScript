%{
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unistd.h>
#include <climits>
#include <dlfcn.h>
#include <llvm/Module.h>
#include <llvm/Function.h>
#include <llvm/PassManager.h>
#include <llvm/CallingConv.h>
#include <llvm/Constants.h>
#include <llvm/ExecutionEngine/ExecutionEngine.h>
#include <llvm/Support/IRBuilder.h>
#include <llvm/System/DynamicLibrary.h>

struct llvm_acotie_ctx {
    llvm::Module* mod;
    llvm::Function* fun;
    llvm::BasicBlock* block;
    llvm::IRBuilder* builder;
    struct {
        llvm::Function* printf;
    } functions;
};

struct llvm_acotie_ctx acotie;

extern int yylex();
extern "C" int yyerror(char const *str);
%}

%union 
{
    char *string;
}

%token LF
%token PRINT
%token <string> STRING
%token SEMICOLON
%token UNKNOWN
%token '{' '}'

%left   XOR
%left	PRINT

%%
program:
	lines { acotie.builder->CreateRetVoid(); }
	;

lines:
	|
	lines block semicolon
	|
	lines line semicolon
	;

block:
	'{' lines '}'
	;

line:
	expression LF
	|
	expression
	;

semicolon:
	|
	semicolon SEMICOLON
	;

expression:
	|
	expression term semicolon
	;

term:
	print
	|
	xor
	;

print:
	PRINT STRING {
        llvm::Function* print_fun = acotie.mod->getFunction("print");
        std::string str($2);
        llvm::GlobalVariable* str_const = new llvm::GlobalVariable(
                llvm::ArrayType::get(llvm::Type::Int8Ty, str.size() + 1),
                true, llvm::GlobalVariable::InternalLinkage,
                llvm::ConstantArray::get(str), "", acotie.mod);
        acotie.builder->CreateCall(print_fun,
            acotie.builder->CreateStructGEP(str_const, 0));
    }
    ;

xor:
	STRING XOR STRING { fprintf(stderr, "おうっふ! xor わかんない＞＜\n"); exit(-1); }

%%

int
yyerror(char const *str)
{
    extern char *yytext;
    fprintf(stderr, "おうっふ! 構文エラー %s '%s' \n", str, yytext);
    return 0;
}

char *source_filename;
char *cmdline_source;
int cmdline_source_seek;
void parse_comandlines(int argc, char **argv)
{
    int ch;
    cmdline_source  = NULL;
    source_filename = NULL;

    if (argc > 1) {
        if (argv[1][0] != '-') {
            source_filename = argv[1];
            return;
        }
    }

    while ((ch = getopt(argc, argv, "e:")) != -1) {
       switch (ch) {
        case 'e':
                  cmdline_source = optarg;
                  cmdline_source_seek = 0;
                  break;
        case '?':
                  break;
        default:
                  break;
        }
    }
    return;
}

#ifdef _GNU_SOURCE
ssize_t cmdline_source_read(void *v, char *buf, size_t size)
#else
int cmdline_source_read(void *v, char *buf, int size)
#endif
{
    int cmdline_source_len = strlen(cmdline_source);
    char *current = cmdline_source + cmdline_source_seek;
    int copy_size;

    if (cmdline_source_len <= cmdline_source_seek) {
        return 0;
    }

    if (strlen(current) < size) {
        copy_size = strlen(current);
    } else {
        copy_size = size;
    }

    memcpy(buf, current, copy_size);
    buf[copy_size] = '\0';
    cmdline_source_seek += copy_size;
    return copy_size;
}

void register_builtins()
{
    static std::string format_str("おうっふー %s");
    llvm::Function* fun = llvm::cast<llvm::Function>(
        acotie.mod->getOrInsertFunction(
            "print", llvm::Type::VoidTy,
            llvm::PointerType::get(llvm::Type::Int8Ty, 0), NULL));
    llvm::BasicBlock* block = llvm::BasicBlock::Create("entry", fun);
    llvm::IRBuilder* builder = new llvm::IRBuilder(block);

    llvm::GlobalVariable* str_const = new llvm::GlobalVariable(
            llvm::ArrayType::get(llvm::Type::Int8Ty, format_str.size() + 1),
            true, llvm::GlobalVariable::InternalLinkage,
            llvm::ConstantArray::get(format_str), "", acotie.mod);
    builder->CreateCall2(acotie.functions.printf,
        builder->CreateStructGEP(str_const, 0),
        fun->arg_begin());

    builder->CreateRetVoid();
}

int main(int argc, char **argv)
{
    extern int yyparse(void);
    extern FILE *yyin;

    parse_comandlines(argc, argv);

    if (cmdline_source != NULL) {
#ifdef _GNU_SOURCE
        cookie_io_functions_t io_funcs = { cmdline_source_read, 0, 0, 0 };

        yyin = fopencookie(0, "r", io_funcs);
#else
        yyin = fropen(0, cmdline_source_read);
#endif
    } else if (source_filename != NULL) {
        FILE* fp = fopen(source_filename, "rb");
        if (!fp) {
            fprintf(stderr, "おふっふ! ファイルが開かない! '%s'", source_filename);
            return 255;
        }
        char buf[BUFSIZ];
        while (fgets(buf, sizeof(buf), fp)) {
            if (strncmp(buf, "#!", 2) == 0) {
                yyin = fp;
            } else {
                fclose(fp);
                yyin = fopen(source_filename, "rb");
            }
            break;
        }
    }

    acotie.mod = new llvm::Module("acotie");

    {
        std::vector<llvm::Type const*> param_types;
        param_types.push_back(llvm::PointerType::get(llvm::Type::Int8Ty, 0));
        acotie.functions.printf = llvm::Function::Create(
            llvm::FunctionType::get(llvm::Type::VoidTy, param_types, true),
            llvm::Function::ExternalLinkage, "printf", acotie.mod);
        acotie.functions.printf->setCallingConv(llvm::CallingConv::C);
    }
    register_builtins();

    acotie.fun = llvm::cast<llvm::Function>(acotie.mod->getOrInsertFunction("acotie_main", llvm::Type::VoidTy, NULL));
    acotie.block = llvm::BasicBlock::Create("entry", acotie.fun);
    acotie.builder = new llvm::IRBuilder(acotie.block);
    if (yyparse()) {
        return 1;
    }
    delete acotie.builder;
    {
        llvm::ExecutionEngine* engine = llvm::ExecutionEngine::create(acotie.mod);
        void (*code)() = reinterpret_cast<void(*)()>(engine->getPointerToFunction(acotie.fun));
        code();
        delete engine;
    }

    return 0;
}
