import 'dart:io';

import 'package:platforms_source_gen/android_gen.dart';
import 'package:platforms_source_gen/gen_file_edit.dart';
import 'package:platforms_source_gen/platforms_source_gen.dart';

import 'file_config.dart';
import 'manager/manager_creater.dart';
import 'utils/android_file_utils.dart';
import 'utils/flutter_file_utils.dart';
import 'utils/ios_file_utils.dart';
import 'auto_gen_class_json.dart';
import 'spi_flutter_package.dart';

Future<void> native2flutter(
  FlutterPlatformConfig flutterConfig,
  bool nullSafeSupport, {
  AndroidPlatformConfig? androidConfig,
  IosPlatformConfig? iosConfig,
}) async {
  Directory directory =
      Directory(flutterConfig.sourceCodePath + "/native2flutter");
  if (!directory.existsSync()) {
    _genFlutterParse(flutterConfig.sourceCodePath, flutterConfig.channelName,
        [], nullSafeSupport);
    return;
  }
  List<GenClassBean> list = await platforms_source_gen_init(
    flutterConfig.sourceCodePath + "/native2flutter", //you dart file path
  );
  if (list.isEmpty) {
    _genFlutterParse(flutterConfig.sourceCodePath, flutterConfig.channelName,
        [], nullSafeSupport);
    return;
  }
  await autoCreateJsonParse(list, directory.path, nullSafeSupport);
  list.forEach((element) {
    element.methods.removeWhere((element) => element.name == "toJson");
  });

  _genFlutterParse(flutterConfig.sourceCodePath, flutterConfig.channelName,
      list, nullSafeSupport);

  ////////////////////////android//////////////////////////
  ////////////////////////android//////////////////////////
  ////////////////////////android//////////////////////////
  if (androidConfig != null) {
    list.forEach((element) {
      //set custom save path
      String classPath = element.path.split(":")[1];
      classPath = "./lib" + classPath.substring(classPath.indexOf("/"));
      Map<int, String> lines = File(classPath).readAsLinesSync().asMap();
      for (int index in lines.keys) {
        if (index == 0) {
          if (lines[index]?.contains("FileConfig") != true) {
            break;
          }
        } else if (lines[index]?.startsWith("//") == true) {
          if (lines[index]?.contains("androidSavePath") == true) {
            element.savePath = lines[index]?.split("=")[1].trim() ?? "";
            element.savePath +=
                "/" + androidConfig.packageName.replaceAll(".", "/");
          }
          //channel name
        }
      }
    });
    JavaFileUtils.genJavaCode(list, androidConfig.packageName,
        androidConfig.savePath, ".native2flutter");
    _gentJavaImpl(list, androidConfig.packageName, androidConfig.savePath,
        nullSafeSupport);
  }

  ////////////////////////ios//////////////////////////
  ////////////////////////ios//////////////////////////
  ////////////////////////ios//////////////////////////
  if (iosConfig != null) {
    ObjcFileUtils.genObjcCode(list, iosConfig.iosProjectPrefix,
        iosConfig.savePath, ".native2flutter");
    ObjcFileUtils.gentObjcImpl(
        list, iosConfig.iosProjectPrefix, iosConfig.savePath);
  }
}

void _genFlutterParse(
  String flutterPath,
  String packageName,
  List<GenClassBean> list,
  bool nullSafeSupport,
) {
  String flutterSavePath = flutterPath + "/generated/channel";
  flutterPath += "/native2flutter";
  packageName += ".native2flutter";
  String importStr = "";
  String methodContent = "";
  list
      .where((classBean) =>
          classBean.classInfo.type == 1 &&
          File(classBean.path).parent.path != flutterSavePath)
      .forEach((classBean) {
    classBean.imports.forEach((element) {
      if (element.startsWith("package:")) {
        importStr += element + "\n";
      } else {
        String newImport = element.replaceRange(
                "import '".length, "import '".length, "../../") +
            "\n";
        if (!importStr.contains(newImport)) {
          importStr += newImport;
        }
      }
    });
    //	T parse<T>(instance, String method, [dynamic args]) {
    // if ("getToken" == method) {
    //       return instance.getToken(args[0], args[1]) as T;
    //     }
    classBean.methods.forEach((method) {
      String argsStr = "";
      String extra = "";
      method.args.asMap().forEach((index, arg) {
        //	Map<dynamic, dynamic> a = (args[0] as Map);
        // 			Map<String,int> result = a.map((key, value) => MapEntry(key as String, value as int));
        extra +=
            "\t\targs[$index] =  ${FlutterFileUtils.createParseCode(arg, paramsName: "args[$index]")};\n";
        argsStr += "args[$index], ";
      });

      String customClassExtra = "";
      if (method.returnType.subType.isNotEmpty) {
        //		return	result.then((value) => "PageInfo___custom___" + jsonEncode(value.toJson()));
        method.returnType.subType[0].name = "value";
        customClassExtra =
            ".then((value) => ${FlutterFileUtils.parseMethodArgs(method.returnType.subType[0])})";
      }
      methodContent +=
          "\t\tif(\"${classBean.classInfo.name}.${method.name}\" == \"\$cls.\$method\") {\n" +
              extra +
              "\t\t\treturn instance.${method.name}($argsStr)$customClassExtra;\n" +
              "\t\t}\n";
    });
  });

  String methodStr =
      "\tdynamic parse(instance, String cls, String method, [dynamic args]) {\n" +
          methodContent +
          "\t}\n";
  String allContent =
      "import 'dart:typed_data';\nimport 'dart:convert';\n$importStr" +
          "extension  IParse on Object{\n" +
          methodStr +
          "}\n";
  if (!nullSafeSupport) {
    allContent = GenFileEdit.removeDartNullSafe(allContent);
  }
  ManagerUtils.dartManagerImport += "import 'parse/object_parse.dart';\n";
  Directory dir = Directory(flutterSavePath + "/parse");
  if (!dir.existsSync()) {
    dir.createSync(recursive: true);
  }
  File impFile = File(dir.path + "/object_parse.dart");
  impFile.writeAsStringSync(allContent);
}

void _gentJavaImpl(
  List<GenClassBean> list,
  String packageName,
  String savePath,
  bool nullSafeSupport,
) {
  //
  // import java.util.ArrayList;
  // import java.util.List;
  //
  // public class IAccountImpl implements IAccount{
  // @Override
  // public void getToken(Long teamId, String userId, ChannelManager.Result<String> callback){
  // List args = new ArrayList();
  // args.add(teamId);
  // args.add(userId);
  // ChannelManager.invoke(this.getClass(), "getToken", args, callback);
  // }
  // }

  packageName += ".native2flutter";
  savePath += "/" + packageName.replaceAll(".", "/");

  list.where((classBean) => classBean.classInfo.type == 1).forEach((classBean) {
    //impl interface
    String methodStr = "";
    classBean.methods.forEach((method) {
      bool hasCallback = false;
      String argNames = "";
      String argsStr = "";
      method.args.forEach((arg) {
        if (arg.type == "ChannelManager.Result") {
          hasCallback = true;
        } else {
          //not include callback
          argNames += "\t\targs.add(${arg.name});\n";
        }
        argsStr += "${JavaCreate.getTypeStr(arg)} ${arg.name}, ";
      });
      if (argsStr.endsWith(", ")) {
        argsStr = argsStr.substring(0, argsStr.length - 2);
      }

      String methodContent = "\t\tList args = new ArrayList();\n" +
          argNames +
          "\t\tChannelManager.invoke(this.getClass().getInterfaces()[0], \"${method.name}\", args, ${hasCallback ? 'callback' : 'null'});\n";
      methodStr += "\t@Override\n" +
          "\tpublic void ${method.name}($argsStr) {\n" +
          methodContent +
          "\t}\n";
    });
    // import com.siyehua.spiexample.channel.native2flutter.Fps;
    // import com.siyehua.spiexample.channel.native2flutter.FpsImpl;
    var finalSavePath = savePath;
    if (classBean.savePath.isNotEmpty) {
      finalSavePath = classBean.savePath;
    }
    String path = finalSavePath.replaceAll("/native2flutter", "");

    var list = ManagerUtils.javaSaveList[path];
    if (list == null) {
      list = [];
      ManagerUtils.javaSaveList[path] = list;
    }
    //todo
    list.add(JavaInfo.create(
        javaManagerImport: "import $packageName.${classBean.classInfo.name};\n"
            "import $packageName.${classBean.classInfo.name}Impl;\n",
        javaImplStr:
            "\t\taddChannelImpl(${classBean.classInfo.name}.class, new ${classBean.classInfo.name}Impl());\n",
        channelName: ""));

    String importStr =
        "import ${packageName.replaceAll(".native2flutter", "")}.ChannelManager;\n" +
            "import ${packageName.replaceAll(".native2flutter", "")}.ChannelManager.Result;\n" +
            "import ${packageName.replaceAll(".native2flutter", "")}.flutter2native.*;\n" +
            "import java.util.List;\n"
                "import java.util.ArrayList;\n"
                "import java.util.HashMap;\n"
                "import org.jetbrains.annotations.NotNull;\n"
                "import org.jetbrains.annotations.Nullable;\n";
    String allContent = "package $packageName;\n\n" +
        importStr +
        "public class ${classBean.classInfo.name}Impl  implements ${classBean.classInfo.name}{\n" +
        methodStr +
        "}\n";
    if (!nullSafeSupport) {
      allContent = GenFileEdit.removeJavaNullSafe(allContent);
    }
    Directory dir = Directory(finalSavePath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    File impFile = File(dir.path + "/${classBean.classInfo.name}Impl.java");
    impFile.writeAsStringSync(allContent);
  });
}
