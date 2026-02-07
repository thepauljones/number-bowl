#run {
    set_build_options_dc(.{do_output = false});

    w := compiler_create_workspace("Number Bowl");
    options := get_build_options(w);
    copy_commonly_propagated_fields(get_build_options(), *options);
    options.output_executable_name = "number_bowl";

    set_build_options(options, w);

    compiler_begin_intercept(w);
    add_build_file("main.jai", w);

    while true {
        message := compiler_wait_for_message();
        if message.kind == {
            case .ERROR;
                exit(1);
            case .COMPLETE;
                break;
        }
    }
    compiler_end_intercept(w);
};

#import "Basic";
#import "Compiler";
