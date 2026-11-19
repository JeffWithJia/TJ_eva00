from launch import LaunchDescription
from launch.actions import DeclareLaunchArgument, IncludeLaunchDescription, LogInfo, OpaqueFunction
from launch.launch_description_sources import PythonLaunchDescriptionSource
from launch.substitutions import LaunchConfiguration, PathJoinSubstitution
from launch_ros.substitutions import FindPackageShare


def _include_apex_tool_launch(launch_file):
    return IncludeLaunchDescription(
        PythonLaunchDescriptionSource(
            PathJoinSubstitution([FindPackageShare("apex_tool"), "launch", launch_file])
        )
    )


def _select_tool(context):
    tool_type = LaunchConfiguration("tool_type").perform(context).strip().lower()
    if tool_type == "dm":
        return [_include_apex_tool_launch("tool_dm.launch.py")]
    if tool_type == "zy":
        return [_include_apex_tool_launch("tool_zy.launch.py")]
    if tool_type in {"wuji", "wujihand"}:
        return [_include_apex_tool_launch("tool_wuji.launch.py")]
    if tool_type in {"none", ""}:
        return [LogInfo(msg="Apex tool disabled: tool_type=none")]
    raise RuntimeError(f"Unsupported tool_type={tool_type}. Expected dm, zy, wuji, or none.")


def generate_launch_description():
    return LaunchDescription(
        [
            DeclareLaunchArgument(
                "tool_type",
                default_value="dm",
                description="Apex tool type: dm, zy, wuji, or none.",
            ),
            OpaqueFunction(function=_select_tool),
        ]
    )
