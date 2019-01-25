#!/bin/bash

# 此脚本用于构建前端和后端项目的docker镜像
# 参数 docker_registry 镜像仓库地址
# 参数 docker_host 远程docker主机，用于ssh-key登陆执行docker build命令并push image
# 参数 project_type 项目类型，fore-end代表前端，back-end代表后端
# 例如 bash docker-build.sh registry.pagoda.com.cn rancher.manager back-end

# 校验参数
if [ "$1"x = "x" ]; then
  print_log "构建失败！缺失参数：docker_registry"
  exit -1
else
  docker_registry=$1
fi

if [ "$2"x = "x" ]; then
  print_log "构建失败！缺失参数：docker_host"
  exit -1
else
  docker_host=$2
fi

if [ "$3"x = "x" ]; then
  print_log "构建失败！缺失参数：project_type"
  exit -1
else
  project_type=$3
fi

# 设置变量
# Jenkins环境变量http://jenkins-bgy.1mxian.com/env-vars.html
remote_workspace_dir=/home/source_to_build
remote_target_dir=${remote_workspace_dir}/${JOB_NAME}
docker_image_name=${docker_registry}/${JOB_NAME}:latest
prefix_boa_open_api="boa_"
prefix_b2b2c_service_api="b2b2c_"
prefix_goodsmgr_api="uni_erp_"
trade_h5_project=("uniseq_trade_h5" "uniseq_buyer_phone_h5")
trade_admin_project=("uniseq_trade_admin" "marketing_admin")
btob_h5_project=("client_manager" "client_wechat" "open_web" "rbac_web")
vendor_admin_project=("uniseq_vendor_admin")

# 构建
function start_build {
  print_log "构建开始..."

  if [ "${project_type}" = "fore-end" ]; then
    fore_end_build
  elif [ "${project_type}" = "back-end" ]; then
    back_end_build
  else
    print_log "构建失败！未知的项目类型${project_type}"
  fi
 
}

# 构建前端
function fore_end_build {
  fore_end_type=0
  currPrjBranch=${JOB_NAME##*_}
  currPrjName=${JOB_NAME%_*}

  print_log "当前前端项目是" ${currPrjName} ${currPrjBranch}

  # 1.判断是否为交易平台H5项目
  for prj in ${trade_h5_project[@]}; do
    if [[ ${JOB_NAME} =~ ${prj} ]]; then
      fore_end_type=1
      break
    fi
  done
   
  if [ ${fore_end_type} -eq 1 ]; then
    print_log "正在编译交易平台H5..."
    #拷贝当前分支配置文件
    cp ${WORKSPACE}/h5/src/conf/${currPrjBranch}.Global.js ${WORKSPACE}/h5/src/actions/Global.js
   
    #需要手动创建styles文件夹
    mkdir -p ${WORKSPACE}/h5/dist/styles

    #默认项目下有node_modules，开始构建
    cd ${WORKSPACE}/h5;
    npm run dist #>/dev/null 2>&1;
    
    #如果失败，先安装模块，再构建
    if [ $? -ne 0 ]; then
      npm install -g cnpm --registry=https://registry.npm.taobao.org >/dev/null 2>&1;
      cnpm install >/dev/null 2>&1;
      cnpm install less less-loader >/dev/null 2>&1;
      npm run dist >/dev/null 2>&1;
    fi

    #如果失败则退出
    if [ $? -eq 0 ]; then
      print_log "编译成功！"
    else
      print_log "编译失败！"
      exit -1;
    fi
    
    #更新资源文件到编译目录
    cp -r ${WORKSPACE}/h5/src/images/. ${WORKSPACE}/h5/dist/images;
    cp -r ${WORKSPACE}/h5/src/sources/. ${WORKSPACE}/h5/dist/sources;
    cp -r ${WORKSPACE}/h5/src/styles/*.css ${WORKSPACE}/h5/dist/styles;
    
    #删除原编译文件目录
    rm -rf ${WORKSPACE}/html/;
    
    #拷贝编译文件到/html
    if [ "$currPrjName" == "uniseq_trade_h5" ]; then
      mkdir -p ${WORKSPACE}/html/trade/h5;
      cp -r ${WORKSPACE}/h5/dist/. ${WORKSPACE}/html/trade/h5;
    else
      mkdir -p ${WORKSPACE}/html/buyer/h5
      cp -r ${WORKSPACE}/h5/dist/. ${WORKSPACE}/html/buyer/h5;
    fi

    #如果失败则退出
    if [ $? -eq 0 ]; then
      print_log "更新编译文件成功！"
    else
      print_log "更新编译文件失败！"
      exit -1;
    fi
    
    #删除源文件，保留node_modules
    #shopt -s extglob && rm -rf !(node_modules);   
    rm -rf cfg dist src test webpack.config.js karma.conf.js test.html package.json server.js

  fi

  # 2.判断是否为交易平台管理台项目
  for prj in ${trade_admin_project[@]}; do
    if [[ ${JOB_NAME} =~ ${prj} ]]; then
      fore_end_type=2
      break
    fi
  done
  
  if [ ${fore_end_type} -eq 2 ]; then
    print_log "正在编译交易平台管理台...";
    
    #切换到项目目录
    if [ "$currPrjName" == "uniseq_trade_admin" ]; then
      cd ${WORKSPACE}/nerp;
    else
      cd ${WORKSPACE}/myApp;
    fi


    #拷贝环境配置文件   
    cp app/cfg/${currPrjBranch}.config.js app/config.js;
    
    #开始构建
    sencha app build >/dev/null 2>&1;

    #如果失败，先升级，在构建 
    if [ $? -eq 0 ]; then
      print_log "编译成功！"
    else
      sencha app upgrade >/dev/null 2>&1;
      if [ $? -ne 0 ]; then
         print_log "编译失败！sencha app upgrade"
         exit -1;
      fi

      sencha app build >/dev/null 2>&1;
      if [ $? -ne 0 ]; then
         print_log "编译失败！sencha app build"
         exit -1;
      fi

      print_log "编译成功！"
    fi
 
    #删除原编译文件目录
    rm -rf ${WORKSPACE}/html/
    
    #拷贝编译文件到/html
    if [ "$currPrjName" == "uniseq_trade_admin" ]; then
      mkdir -p ${WORKSPACE}/html/trade/admin;
      cp -r ${WORKSPACE}/nerp/build/production/nerp/. ${WORKSPACE}/html/trade/admin;
      rm -rf ${WORKSPACE}/nerp;
    else
      # 如果是 marketing admin 不创建默认目录
      # mkdir -p ${WORKSPACE}/html/marketing/admin;
      cp -r ${WORKSPACE}/myApp/build/production/myApp/. ${WORKSPACE}/html;
      rm -rf ${WORKSPACE}/myApp
    fi
 
    if [ $? -eq 0 ]; then
      print_log "更新编译文件成功！"
    else
      print_log "更新编译文件失败！"
      exit -1;
    fi

  fi

  # 3.判断是否为大客户平台H5项目
  for prj in ${btob_h5_project[@]}; do
    if [[ ${JOB_NAME} =~ ${prj} ]]; then
      fore_end_type=3
      break
    fi
  done
  
  if [ ${fore_end_type} -eq 3 ]; then
    print_log "正在编译大客户H5...";

    if [ -d dist ];then
      rm -rf dist
    fi
     
    #默认项目下有node_modules，开始构建
    npm run ${currPrjBranch} >/dev/null 2>&1;
   
    #如果失败，先安装模块，再构建
    if [ $? -ne 0 ]; then
      npm install -g cnpm --registry=https://registry.npm.taobao.org >/dev/null 2>&1;
      cnpm install >/dev/null 2>&1;
      npm run ${currPrjBranch} >/dev/null 2>&1;
    fi

    #如果失败则退出
    if [ $? -eq 0 ]; then
      print_log "编译成功！"
    else
      print_log "编译失败！"
      exit -1;
    fi   
   
    #删除原编译文件目录
    rm -rf ${WORKSPACE}/src/;
    rm -rf ${WORKSPACE}/html/

    #拷贝编译文件到/html
    if [ "$currPrjName" == "client_manager" ]; then
      mkdir -p ${WORKSPACE}/html/;
      cp -r ${WORKSPACE}/dist/. ${WORKSPACE}/html/;
    else
      mkdir -p ${WORKSPACE}/html/
      cp -r ${WORKSPACE}/dist/. ${WORKSPACE}/html/;
    fi

    #如果失败则退出
    if [ $? -eq 0 ]; then
      print_log "更新编译文件成功！"
    else
      print_log "更新编译文件失败！"
      exit -1;
    fi

  fi

  # 4.判断是否为uniseq_vendor_admin项目
  for prj in ${vendor_admin_project[@]}; do
    if [[ ${JOB_NAME} =~ ${prj} ]]; then
      fore_end_type=4
      break
    fi
  done
 
  if [ ${fore_end_type} -eq 4 ]; then
    print_log "即将拷贝到192.168.1.58上编译...";
  fi

  # 清理和远程拷贝
  clean_and_copy

  # 构建
  print_log "正在构建${docker_registry}/${JOB_NAME}:latest镜像..."
  build_image ${remote_target_dir} ${docker_registry}/${JOB_NAME}:latest
}


# 构建后端
function back_end_build {
  # 基于jenkins maven构建后的war包打镜像
  
  # 1.清理和远程拷贝
  clean_and_copy

  is_war_deploy="false"

  # 2.执行docker build和docker push命令
  for path_to_war in `find -name *.war`; do
    is_war_deploy="true"
    sub_project_name=`echo ${path_to_war}|cut -d / -f 2`

    if [ "${sub_project_name}" = "target" ]; then
      print_log "正在构建${docker_image_name//-/_}镜像..."
      build_image ${remote_target_dir} ${docker_image_name}
    else
      p_name=`eval echo '$'"prefix_"${JOB_NAME%_*}`
      img_name=${docker_registry}/${p_name}${sub_project_name//-/_}_${JOB_NAME##*_}:latest
      print_log "正在构建${img_name}镜像..."
      build_image ${remote_target_dir}/${sub_project_name} ${img_name} 
    fi

  done
  
  # 如果不是war
  if [ "${is_war_deploy}" = "false" ]; then
    print_log "正在构建${docker_image_name}镜像..."
    build_image ${remote_target_dir} ${docker_image_name}
  fi
}

# 构建镜像
function build_image {

  target_dir=$1
  image_name=${2//-/_}

  # 如果是uniseq_vendor_admin还需要先构建
  if [ "$currPrjName" == "uniseq_vendor_admin" ]; then
    print_log "正在编译交易平台管理台...";
    ssh root@${docker_host} "cd ${target_dir} && /home/source_to_build/build_vendor_admin.sh ${currPrjBranch}"
    if [ $? -eq 0 ]; then
    print_log "项目编译成功！"
  else
    print_log "项目编译失败！sencha出错"
    exit -1
  fi
  fi

  ssh ${docker_host} "cd ${target_dir} \
    && docker build -t ${image_name} . \
    && docker push ${image_name} "

  if [ $? -eq 0 ]; then
    print_log "构建成功！"
  else
    print_log "构建失败！docker build出错"
    exit -1
  fi
}

# 远程拷贝
function clean_and_copy {
  # 1.删除远程旧项目代码目录
  ssh ${docker_host} "if [ ! -d ${remote_target_dir} ]; then \
      mkdir -p ${remote_workspace_dir}; \
      echo [$(date '+%Y-%m-%d %H:%M:%S')] \"已创建远程工作空间目录${remote_target_dir//-/_}\"; \
    fi"
  #ssh ${docker_host} "if [ -d ${remote_target_dir} ]; then \
  #    rm -rf ${remote_target_dir}; \
  #    if [ $? -eq 0 ]; then \
  #      echo [$(date '+%Y-%m-%d %H:%M:%S')] \"已删除远程旧项目代码目录${remote_target_dir}\"; \
  #   fi \
  #  fi"

  # 2.远程拷贝项目代码
  print_log "开始远程拷贝代码..."
  cd ${WORKSPACE}
  #prsync -r -a -H root@${docker_host} ${WORKSPACE} ${remote_target_dir}
  if [ "${project_type}"x = "fore-end"x ]; then
    if [ "$currPrjName" == "uniseq_vendor_admin" ]; then
      rsync -aqH * root@${docker_host}:${remote_target_dir}
    else
      if [ -f "nginx.conf" ]; then
        rsync -aqH nginx.conf root@${docker_host}:${remote_target_dir}/
      fi
      rsync -aqH Dockerfile root@${docker_host}:${remote_target_dir}/
      rsync -aqH ./html root@${docker_host}:${remote_target_dir}/
    fi
  else
    rsync -aqH * root@${docker_host}:${remote_target_dir}
  fi

  if [ $? -eq 0 ]; then
    print_log "远程拷贝代码成功！"
  else
    print_log "构建失败！远程拷贝代码出错"
    exit -1
  fi
}

# 打印日志
function print_log {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')]" $@
}

# 开始构建
start_build
