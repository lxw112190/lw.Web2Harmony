document.querySelector('#status').textContent='JS 模块加载成功；中文路径与图片请在真机确认';
let count=Number(localStorage.getItem('count')||0);
const update=()=>document.querySelector('#counter').textContent='本地存储计数：'+count;
update();document.querySelector('#count').onclick=()=>{count++;localStorage.setItem('count',String(count));update()};
