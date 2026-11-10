# Godot 4.6 原生关卡工作台

实现目标：在Godot顶部主屏增加KuroBox入口，关卡库→单关绘制→原生Inspector参数→共享规则试关→回放验证→发布到正式清单。保持现有八关与运行时工坊可用。

## 共享参数契约

ObjectCatalog加@tool。parameter_schema(type_id:String)->Array[Dictionary]，每项{id,label,type,min,max,options,description}；默认值来自类型定义同名字段，不重复存默认。resolve_instance(instance:Dictionary)->Dictionary返回类型定义与受限params覆盖后的副本；validate_parameters(instance)->Array[String]。params可选，无覆盖时旧关卡行为不变。

bag: punch_distance(int 1–16，默认既有2)；plate: activation_filter(enum all/player/boxes，默认all)；door: gate_logic(enum any/all，默认any)。三项均进入真实模拟和验证。Catalog提供create_variant(source_id,new_id,label,overrides)->Error，保存默认canonical定义文件；write_definition_document(document,path)->Error可用于隔离测试，先校验再原子写入；catalog_document()->Dictionary；reload_catalog保持明确错误，不调用预加载Script的内置reload。

ReplayProof为core/replay_proof.gd，@tool RefCounted，static revision(level)->String，build(level,commands:Array[String])->Dictionary，verify(level,proof)->Dictionary。返回{valid:bool,revision:String,commands:Array,moves:int,punches:int,errors:Array}；verify必须实际重放并确认获胜，不只比hash。revision含规则相关布局、实例params及有效类型默认值，排除title和metadata。BoardState加device_debug()->Array[Dictionary]，提供{id,behavior,pressed/open,powered_by,held_open,logic/filter}，供UI格式化。

## 工作区服务

LevelWorkspace @tool RefCounted（不得依赖EditorInterface）：configure(config:Dictionary={})，默认campaign_path=res://content/levels/campaign.json，published_dir=res://content/levels，draft_dir=res://content/workshop/drafts，proof_dir=res://content/workshop/proofs。

last_errors:Array[String]，list_levels()->Array[Dictionary]返回{id,title,status,published_path,draft_path,revision,published_hash,draft_hash}，status为published/draft/modified。
load_level(id)->Dictionary（草稿优先），new_level(id,title,width=10,height=8)->Dictionary，duplicate_level(id,new_id,title)->Dictionary（创建并保存草稿，清除旧proof/solution），save_draft(level,expected_hash="")->Error（允许未完成谜题），save_proof(level,proof)->Error，load_proof(id)->Dictionary，publish(level,proof,expected_published_hash="")->Error，save_order(ids:Array[String])->Error（仅发布关，完整集合，更新campaign）。source_hash(path)->String。

发布需严格Codec和ReplayProof.verify。已有发布文件不被保存草稿修改。新发布自动登记清单，稳定id与显示title分开。检测外部修改，不静默覆盖；单文件临时写入替换；发布多文件失败必须保留/恢复原有效文件。测试使用传入临时路径，不改真实八关或定义。

## 绘制控件公共接口

LevelEditor @tool，embedded_mode:bool（在add_child前设true），native_inspector:bool=true，use_external_history:bool=false。
信号 document_changed(before:Dictionary,after:Dictionary,label:String)，selection_changed(instance_id:String)，proof_recorded(proof:Dictionary)，test_state_changed(debug:Array[Dictionary],summary:Dictionary)。
现有setup/get_level/undo_edit/redo_edit保留。新接口 apply_document(level:Dictionary)（历史恢复，不清除视角/不发新的历史事务），apply_instance_parameter(id,field,value,record_history=true)->bool，clear_instance_parameter(id,field,record_history=true)->bool，select_instance(id)，begin_test()，get_last_proof()->Dictionary，play_verified_replay()->bool，refresh_catalog()。

编辑器工具模式限制输入仅当前可见工作台/其焦点内。embedded模式使用引擎主题，不启动音频和游戏背景，不显示冗余导入/导出/返回按钮（上层工作台接管文件生命周期）。试关在工作台内部运行共享BoardState，记录有效命令/必要朝向变化、撤销同步命令、重开清空；成功时生成proof并发信号。返回保留文档/画笔/选区/缩放平移。调试面板显示真实门/压板因果。滚轮以光标为中心缩放、中键平移、适配全图。

## 原生集成

EditorPlugin顶部主屏，插件卸载时断开/释放自己的节点并清理本插件Inspector目标。Inspector Resource通过_get_property_list暴露整份params，EditorProperty发出修改意图，由工作台先校验新参数再登记文档前后快照。撤销能恢复“没有覆盖”，也能还原修复前的无效原值，不会因重新校验旧值而丢失历史。绘制与参数修改共享EditorUndoRedoManager显式全局资源上下文，逐操作force_fixed_history，避免误挂到当前tscn。后端apply_document不重复登记。原生Inspector使用稳定实例id，跨关撤销会切回受影响文档并清理旧目标。

原生UI关卡库提供搜索/状态/缩略图、新建、复制、排序、保存草稿、发布；未保存切换要明确处理。发布与结构检查、实际通关证明分开显示。全部截图必须来自真实Godot Editor，不能只截独立运行场景冒充。
