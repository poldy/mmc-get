:- module manager.
:- interface.
:- import_module package, io.

:- pred update_packages(io::di, io::uo) is det.

:- pred packages(package::out) is nondet.
:- pred unreviewed(package::out) is nondet.

:- implementation.
:- use_module dir, ioextra.
:- import_module maybe, list, string, exception.

:- mutable(reviewed, list(package), [], ground, [untrailed, attach_to_io_state]).
:- mutable(unreviewed, list(package), [], ground, [untrailed, attach_to_io_state]).
:- initialize init_packages/2.

:- pred package_paths(string::out, string::out, string::out, string::out, io::di, io::uo) is det.
package_paths(Reviewed, Unreviewed, ReviewedUrl, UnreviewedUrl, !IO) :-
    configdir(Config, !IO),
    ioextra.mkdir(Config, !IO),
    Reviewed = dir.(Config / "reviewed.list"),
    Unreviewed = dir.(Config / "unreviewed.list"),
    io.get_environment_var("MERCURY_PKG_PATH", PkgPath, !IO),
    Prefix = maybe.maybe_default("https://mercury-in.space/packages", PkgPath),
    string.append(Prefix, "/packages.list", ReviewedUrl),
    string.append(Prefix, "/unreviewed.list", UnreviewedUrl).

update_packages(!IO) :-
    package_paths(Reviewed, Unreviewed, ReviewedUrl, UnreviewedUrl, !IO),
    io.call_system("curl -o " ++ Reviewed ++ " " ++ ReviewedUrl, Res1, !IO),
    io.call_system("curl -o " ++ Unreviewed ++ " " ++ UnreviewedUrl, Res2, !IO),
    ( if
        Res1 = ok(0),
        Res2 = ok(0)
    then
        true
    else
        throw("curl failed")
    ).

:- pragma promise_pure packages/1.
packages(P) :-
    semipure get_reviewed(Ps),
    list.member(P, Ps).

:- pragma promise_pure unreviewed/1.
unreviewed(P) :-
    semipure get_unreviewed(Ps),
    list.member(P, Ps).

:- pred init_packages(io::di, io::uo) is det.
init_packages(!IO) :-
    package_paths(Reviewed, Unreviewed, _, _, !IO),
    load_packages(Res1, Reviewed, !IO),
    load_packages(Res2, Unreviewed, !IO),
    ( if
        Res1 = ok(P1),
        Res2 = ok(P2)
    then
        set_reviewed(P1, !IO),
        set_unreviewed(P2, !IO)
    else if
        Res1 = error(E1),
        Res2 = error(E2),
        sub_string_search(string({E1,E2}), "the term read did not have the right type", _)
    then
        io.format(io.stderr_stream,
            "Failed to parse package lists. You may need to update mmc-get.\n"
            ++ "Check: %s\nCheck: %s\n", [s(Reviewed), s(Unreviewed)], !IO),
        io.set_exit_status(1, !IO)
    else
        true
    ).

:- type maybeio == (pred(maybe(string), io, io)).
:- inst maybeio == (pred(out, di, uo) is det).
:- func (maybeio::in(maybeio)) // (maybeio::in(maybeio))
    = (maybeio::out(maybeio)).
A // B = C :-
    C = (pred(Res::out, !.IO::di, !:IO::uo) is det :-
        A(Res1, !IO),
        (
            Res1 = Res @ yes(_)
        ;
            Res1 = no,
            B(Res, !IO)
        )).

:- pred configdir(string::out, io::di, io::uo) is det.
configdir(Config, !IO) :-
    GetConfig = get_environment_var("XDG_CONFIG_HOME")
        // get_environment_var("APPDATA")
        // (pred(Res::out, !.IO::di, !:IO::uo) is det :-
            get_environment_var("HOME", Res1, !IO),
            (
                Res1 = Res @ no
            ;
                Res1 = yes(Homedir),
                Res = yes(dir.(Homedir / ".config"))
            )),
    GetConfig(ConfigRes, !IO),
    (
        ConfigRes = yes(Config0),
        Config = dir.(Config0 / "mmc-get")
    ;
        ConfigRes = no,
        throw("unable to determine user config dir")
    ).
