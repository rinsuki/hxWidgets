package wx.widgets;

import haxe.macro.Expr.ExprDef.EConst;
import haxe.macro.Expr.Field;
import haxe.macro.Context;
import haxe.io.Path;
import sys.FileSystem;
import sys.io.Process;

typedef OSVersion = {
    var major:Int;
    var minor:Int;
    @:optional var revision:Int;
}

class EntryMacro {

    private static function getOSVersion():OSVersion {
        var version:OSVersion = {
            major: 0,
            minor: 0,
            revision: 0
        };

        if (~/mac/i.match (Sys.systemName ())) {
            var versionString:String = new Process("sw_vers", ["-productVersion"]).stdout.readAll().toString();
            var arr = versionString.split(".");
            version = {
                major: Std.parseInt(arr[0]),
                minor: Std.parseInt(arr[1]),
                revision: Std.parseInt(arr[2])
            };
        }
        return version;
    }

    macro public static function wxconfig():Array<Field> {
        var _pos = Context.currentPos();
        var _class = Context.getLocalClass();
        var _info = Context.getPosInfos(_pos);

        var sourcePath = Path.directory(_info.file);
        if( !Path.isAbsolute(sourcePath) ) {
            sourcePath = Path.join([Sys.getCwd(), sourcePath]);
        }
        sourcePath = Path.normalize(sourcePath);

        var libPath = Path.normalize(Path.join([sourcePath, '../../../']));
        var define = '<set name="HXWIDGETS_PATH" value="$libPath/"/>';

        var os:OSVersion = getOSVersion();
        if (~/windows/i.match(Sys.systemName())) {
            _class.get().meta.add(":buildXml", [{ expr:EConst( CString( '$define\n<include name="${libPath}/Build.xml"/>' ) ), pos:_pos }], _pos );
        } else {
            if (!checkWxConfig()) {
                Context.fatalError("The wx-config executable wasn't found in your PATH, and is required for compilation", _pos);
            }

            var makeFlag = function (s:String):String {
                return '<compilerflag value="$s" />';
            };

            var config = new Process("wx-config", ["--cxxflags"]);
            var cflags = config.stdout.readAll().toString().split("\n")[0].split(" ").map(makeFlag).join("\n");
            config.exitCode();

            #if WEBVIEW
            var config = new Process("wx-config", ["--libs", "gl,std,propgrid,webview"]);
            #else
            var config = new Process("wx-config", ["--libs", "gl,std,propgrid"]);
            #end
            var libs = config.stdout.readAll().toString().split("\n").join(" ").split(" ");
            var link = [];
            var i = 0;
            while (i < libs.length) {
                if (libs[i] == "-framework") {
                    link.push('<vflag name="${libs[i]}" value="${libs[i+1]}"/>');
                    i++;
                } else if (libs[i] != "") {
                    link.push('<lib name="${libs[i]}" />');
                }

                i++;
            }
            config.exitCode();

            cflags += "\n<compilerflag value=\"-I${HXWIDGETS_PATH}/include\" />\n";
            cflags += "\n<compilerflag value=\"-DwxUSE_GRAPHICS_CONTEXT\" />\n";
            cflags += "\n<file name=\"${HXWIDGETS_PATH}/include/custom/wxownerdrawnpanel.cpp\" />\n";

            if (~/mac/i.match(Sys.systemName()) && (os.major > 10 || (os.major == 10 && os.minor >= 7))) {
                #if !NO_CPP_11

                cflags += '\n<compilerflag value="-mmacosx-version-min=10.7" />\n<compilerflag value="-std=c++11" />\n<compilerflag value="-stdlib=libc++" />\n';
                link.push('<compilerflag value="-std=c++11" />');
                link.push('<compilerflag value="-stdlib=libc++" />');
                link.push('<lib name="-lc++" />');

                #end
            }

            var buildXml = {
                expr:EConst( CString( '$define
                                       <set name="MAC_USE_CURRENT_SDK" value="1" if="macos" />
                                       <set name="HXCPP_GCC" value="1" if="macos" />
                                       <set name="HXCPP_M64" value="1" if="macos" />
                                       <files id="haxe">$cflags</files>
                                       <target id="haxe" tool="linker" toolid="exe">${link.join("\n")}</target>' ) ),
                pos:_pos
            };
            _class.get().meta.add(":buildXml", [buildXml], _pos );
        }

        return Context.getBuildFields();
    }

    static function checkWxConfig():Bool {
        for (path in Sys.getEnv("PATH").split(":")) {
            if (FileSystem.exists(Path.join([path, "wx-config"]))) {
                return true;
            }
        }

        return false;
    }

}
