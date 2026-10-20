import UIKit

/// Sticker frames normalized from the supplied library; opening coordinates exclude decoration.
enum DiaryPhotoFrameCatalog {
    struct Item: Identifiable {
        let id: String
        let title: String
        let opening: CGRect
        var image: UIImage? { UIImage(named: id) }
    }
    static let items: [Item] = [
        Item(id: "diary_frame_81599c4dbb", title: "咖啡吧台暖白卷角", opening: CGRect(x: 0.164198, y: 0.109405, width: 0.682914, height: 0.780566)),
        Item(id: "diary_frame_1794e316eb", title: "暖白卷角", opening: CGRect(x: 0.045521, y: 0.031342, width: 0.884710, height: 0.868481)),
        Item(id: "diary_frame_977e6006c7", title: "一窗一景", opening: CGRect(x: 0.147215, y: 0.145550, width: 0.655025, height: 0.617191)),
        Item(id: "diary_frame_cfe9c71f9a", title: "东方明珠与人物全身_胶带", opening: CGRect(x: 0.092010, y: 0.139847, width: 0.798609, height: 0.717330)),
        Item(id: "diary_frame_64000cb2ca", title: "倚栏拿花_镂空无字", opening: CGRect(x: 0.125984, y: 0.085162, width: 0.512577, height: 0.684588)),
        Item(id: "diary_frame_62154094ae", title: "右下园林_镂空", opening: CGRect(x: 0.165049, y: 0.195815, width: 0.666101, height: 0.626649)),
        Item(id: "diary_frame_40f4355996", title: "右下荷花_镂空", opening: CGRect(x: 0.217463, y: 0.186520, width: 0.586810, height: 0.602202)),
        Item(id: "diary_frame_9754e7d86e", title: "回头的一刻_无字", opening: CGRect(x: 0.130435, y: 0.112150, width: 0.636573, height: 0.785673)),
        Item(id: "diary_frame_d7c70c3d97", title: "回头这一刻_镂空无字", opening: CGRect(x: 0.104675, y: 0.161259, width: 0.688444, height: 0.466591)),
        Item(id: "diary_frame_c3a046d48f", title: "园林里的光影", opening: CGRect(x: 0.177893, y: 0.125316, width: 0.655114, height: 0.598551)),
        Item(id: "diary_frame_2aed1fbd2a", title: "女生拍摄陆家嘴夜景_胶带", opening: CGRect(x: 0.092007, y: 0.227754, width: 0.805224, height: 0.571131)),
        Item(id: "diary_frame_ffa75cda88", title: "把夜色留住_无字", opening: CGRect(x: 0.146307, y: 0.206744, width: 0.688274, height: 0.627539)),
        Item(id: "diary_frame_7ffa577d63", title: "撑伞持灯", opening: CGRect(x: 0.083430, y: 0.055391, width: 0.831065, height: 0.857843)),
        Item(id: "diary_frame_8073b107ff", title: "桂花香的苏州", opening: CGRect(x: 0.140320, y: 0.113855, width: 0.690853, height: 0.624945)),
        Item(id: "diary_frame_db35575ef6", title: "桥边停一停_镂空无字", opening: CGRect(x: 0.258315, y: 0.113876, width: 0.666410, height: 0.526925)),
        Item(id: "diary_frame_6af5b15a20", title: "梧桐街道_双胶带", opening: CGRect(x: 0.122917, y: 0.172570, width: 0.726514, height: 0.698022)),
        Item(id: "diary_frame_0689278c91", title: "河埠头的水声", opening: CGRect(x: 0.144128, y: 0.111570, width: 0.707358, height: 0.646693)),
        Item(id: "diary_frame_9aaff1b86a", title: "洋房楼梯留影", opening: CGRect(x: 0.236872, y: 0.101514, width: 0.582788, height: 0.698604)),
        Item(id: "diary_frame_5904e10b83", title: "洋房楼梯花叶票据", opening: CGRect(x: 0.163842, y: 0.122727, width: 0.541550, height: 0.627490)),
        Item(id: "diary_frame_63908a77c6", title: "洋房草坪长椅", opening: CGRect(x: 0.259570, y: 0.165868, width: 0.629539, height: 0.663342)),
        Item(id: "diary_frame_410b032fbe", title: "淡蓝汉服花窗", opening: CGRect(x: 0.176904, y: 0.170080, width: 0.599986, height: 0.597663)),
        Item(id: "diary_frame_e7161ec5e5", title: "湖畔景色", opening: CGRect(x: 0.123730, y: 0.180220, width: 0.712806, height: 0.616749)),
        Item(id: "diary_frame_42d9e15407", title: "湖边餐桌", opening: CGRect(x: 0.099620, y: 0.128205, width: 0.780703, height: 0.693189)),
        Item(id: "diary_frame_18ed59f0ff", title: "灯光在身后_无字", opening: CGRect(x: 0.171282, y: 0.159641, width: 0.663662, height: 0.699495)),
        Item(id: "diary_frame_ee5cecdfd5", title: "白裙水巷_花枝与无字纸条", opening: CGRect(x: 0.302205, y: 0.042457, width: 0.570790, height: 0.686449)),
        Item(id: "diary_frame_41373ebf07", title: "白裙近景_花枝与胶带", opening: CGRect(x: 0.094039, y: 0.209693, width: 0.610222, height: 0.588767)),
        Item(id: "diary_frame_fcab74596d", title: "簪花细节", opening: CGRect(x: 0.174721, y: 0.156493, width: 0.633818, height: 0.667317)),
        Item(id: "diary_frame_dd5fee6df2", title: "红叶廊下_枫叶与无字纸条", opening: CGRect(x: 0.223427, y: 0.183908, width: 0.562848, height: 0.590396)),
        Item(id: "diary_frame_6950b1211b", title: "花窗红枫_木窗竹枝", opening: CGRect(x: 0.323718, y: 0.117733, width: 0.325702, height: 0.671848)),
        Item(id: "diary_frame_1252486d05", title: "苏州水乡纸边", opening: CGRect(x: 0.068933, y: 0.144078, width: 0.820189, height: 0.661334)),
        Item(id: "diary_frame_ff7be467dc", title: "蓝裙侧影_胶带", opening: CGRect(x: 0.223594, y: 0.180288, width: 0.583996, height: 0.617781)),
        Item(id: "diary_frame_85e952845d", title: "蓝裙河岸_胶带与无字纸条", opening: CGRect(x: 0.227561, y: 0.174312, width: 0.476244, height: 0.600608)),
        Item(id: "diary_frame_b398250f22", title: "蓝调人像_无字图注纸条", opening: CGRect(x: 0.135346, y: 0.149293, width: 0.630461, height: 0.544966)),
        Item(id: "diary_frame_9b16ec0763", title: "街角洋房与单车", opening: CGRect(x: 0.217578, y: 0.148084, width: 0.553458, height: 0.685252)),
        Item(id: "diary_frame_d0136a6d1f", title: "衣袖细节", opening: CGRect(x: 0.207442, y: 0.192000, width: 0.609866, height: 0.614843)),
        Item(id: "diary_frame_0d320dbabd", title: "诚品书店女生阅读_镂空含胶带", opening: CGRect(x: 0.074977, y: 0.132450, width: 0.834076, height: 0.648699)),
        Item(id: "diary_frame_f625a5255e", title: "灯影落进河里", opening: CGRect(x: 0.066605, y: 0.211712, width: 0.755947, height: 0.645726)),
        Item(id: "diary_frame_15003062b9", title: "船上晚风与水色", opening: CGRect(x: 0.036585, y: 0.162516, width: 0.730156, height: 0.646903)),
        Item(id: "diary_frame_65ffe1a6dd", title: "大虾", opening: CGRect(x: 0.156000, y: 0.195021, width: 0.709889, height: 0.558392)),
        Item(id: "diary_frame_5677d18169", title: "湖鲜一口", opening: CGRect(x: 0.170213, y: 0.273674, width: 0.615344, height: 0.484435)),
        Item(id: "diary_frame_75291a4942", title: "螺蛳", opening: CGRect(x: 0.210663, y: 0.213348, width: 0.613138, height: 0.586987)),
        Item(id: "diary_frame_467d6c6abf", title: "蟹黄", opening: CGRect(x: 0.144022, y: 0.168844, width: 0.701290, height: 0.576836)),
        Item(id: "diary_frame_4ed7524bd6", title: "廊下听雨", opening: CGRect(x: 0.079167, y: 0.114035, width: 0.826035, height: 0.765262)),
        Item(id: "diary_frame_d95bc23c2f", title: "楼台入水", opening: CGRect(x: 0.205882, y: 0.140054, width: 0.604611, height: 0.682762)),
        Item(id: "diary_frame_0dd6dca833", title: "水波轻晃", opening: CGRect(x: 0.229583, y: 0.128136, width: 0.610748, height: 0.627252)),
        Item(id: "diary_frame_0029c7a8ec", title: "窗影入池", opening: CGRect(x: 0.208900, y: 0.137363, width: 0.587799, height: 0.685219)),
        Item(id: "diary_frame_ede76dbcfb", title: "红叶照水", opening: CGRect(x: 0.115044, y: 0.099900, width: 0.742671, height: 0.796262)),
        Item(id: "diary_frame_ed993f6e1e", title: "花窗借景", opening: CGRect(x: 0.365245, y: 0.109218, width: 0.515794, height: 0.475390)),
        Item(id: "diary_frame_eac2df4b3c", title: "湖畔晚风刚好", opening: CGRect(x: 0.031904, y: 0.095506, width: 0.917207, height: 0.747955)),
        Item(id: "diary_frame_4bd4c7dbf7", title: "煮一壶热茶", opening: CGRect(x: 0.081557, y: 0.139344, width: 0.790007, height: 0.638193)),
        Item(id: "diary_frame_31368e04ed", title: "石间回望", opening: CGRect(x: 0.054545, y: 0.084270, width: 0.810156, height: 0.808451)),
        Item(id: "diary_frame_bce1a282d6", title: "窗边停留", opening: CGRect(x: 0.223404, y: 0.239206, width: 0.721075, height: 0.391553)),
        Item(id: "diary_frame_79d0ae6346", title: "船上留影", opening: CGRect(x: 0.085167, y: 0.181939, width: 0.828112, height: 0.688200)),
        Item(id: "diary_frame_58e7860208", title: "花窗旁的回望", opening: CGRect(x: 0.143969, y: 0.205746, width: 0.711707, height: 0.649268)),
        Item(id: "diary_frame_539ead4430", title: "门内的光与影", opening: CGRect(x: 0.127436, y: 0.095238, width: 0.678679, height: 0.580196)),
    ]
    static var defaultFrame: Item { items.first { $0.id == "diary_frame_1252486d05" } ?? items[0] }
}
