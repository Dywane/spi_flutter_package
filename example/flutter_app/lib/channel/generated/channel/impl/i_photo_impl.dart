import '../channel_manager.dart';
import '../../../flutter2native/other_busniess.dart';
import 'dart:convert';
import 'dart:typed_data';
class IPhotoImpl  implements IPhoto, PackageTag{
	@override
	void aaa() async{
		Type _clsType = IPhoto;
		 ChannelManager.invoke('com.siyehua.example.otherChannelName', package, _clsType.toString(), "aaa", "", );
	}
	@override
	String package = "com.siyehua.example.chanel2.flutter2native";
}
