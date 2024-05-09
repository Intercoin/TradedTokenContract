const http = require('http');
const path = require('path');
const fs = require('fs');
const util = require('util');

const { URL } = require('url');
const { parse: parseQuery } = require('querystring');

const PORT=8080; 
const serverOrigin = 'http://localhost:'+PORT;

const directoryPath = path.join(__dirname, 'data');

const jsonsInDir = fs.readdirSync(directoryPath).filter(file => path.extname(file) === '.json');

var seriesData = [];

jsonsInDir.forEach(file => {
    const fileData = fs.readFileSync(path.join(directoryPath, file));
    //console.log(fileData.toString());
    try {
        const json = JSON.parse(fileData.toString());  
        if (!json.title || !json.data) {
            console.log("wrong format in " + file);
        } else {
            const json = JSON.parse(fileData.toString());    
            //console.log(json);
            seriesData.push({"title":json.title, "data": json.data});
        }
    } catch (e) {
        console.log("wrong json in " + file);
    }

    //const json = JSON.parse(fileData.toString());
    //console.log(JSON.parse(data));
  


});

    var refreshTimeSecDefault =0;
    var refreshTimeSec =0;
var generateHtml = function () {
    var optionsHtml = ``;
    seriesData.forEach(function(element, index){
        optionsHtml += `<option value="${index}">${element.title}</option>`;
    })

    return `
<select id="seriesList">${optionsHtml}</select>
<button id="add">Add</button>
<button id="clear">Clear</button>
<button id="drawAll">DrawAll</button>
<script src="https://code.highcharts.com/highcharts.js"></script>
<!--
<script src="https://code.highcharts.com/stock/highstock.js"></script>
<script src="https://code.highcharts.com/stock/modules/exporting.js"></script>
-->
<div id="container" style="height: 600px;min-width: 600px;"></div>
<script>
function dataJSONGet(index)
{
    var xmlHttp = new XMLHttpRequest();
    xmlHttp.open( "GET", '${serverOrigin}/get?id='+index, false ); // false for synchronous request
    xmlHttp.send( null );
    return JSON.parse(xmlHttp.responseText);
}

//var chart = Highcharts.stockChart('container', {
    var chart = Highcharts.chart('container', {
    chart: {
        zoomType: 'xy'
    },
    scrollbar: {
        barBorderRadius: 0,
        barBorderWidth: 1,
        buttonsEnabled: true,
        height: 14,
        margin: 0,
        rifleColor: '#333',
        trackBackgroundColor: '#f2f2f2',
        trackBorderRadius: 0
    },
    // tooltip: {
    //     formatter: function () {
    //         return this.points.reduce(function (s, point) {
    //             return s + '<br/>' + point.series.name + ': ' +
    //                 point.y + 'm';
    //         }, '<b>' + this.x + '</b>');
    //     },
    //     shared: true
    // },
    legend: {
        layout: 'vertical',
        align: 'left',
        x: 80,
        verticalAlign: 'top',
        y: 55,
        floating: true,
        backgroundColor:
            Highcharts.defaultOptions.legend.backgroundColor || // theme
            'rgba(255,255,255,0.25)'
    }
});


chart.redraw();

function addChartSeries(index) {
    var json = dataJSONGet(index);

    if (typeof json.data.series !== 'undefined' && typeof json.data.series === 'object' && json.data.series.length>1) {
        json.data.series.forEach(function(i){
          
            i.data = i.data.map(function(x) { 
                if (typeof x == 'string') {
                    return parseFloat(x);
                } else {
                    x.y = parseFloat(x.y);
                    return x;
                }    
            
            });
            chart.addAxis(i);
            chart.addSeries(i);
        });
    } else {
    
        chart.addSeries({                        
            name: json.title,
            data: json.data
        }, false);
        
    }
    chart.redraw();
}
var buttonAdd = document.getElementById("add");
var buttonClear = document.getElementById("clear");
var buttonDrawAll = document.getElementById("drawAll");
var select = document.getElementById("seriesList");

buttonAdd.addEventListener("click",function(e){
    buttonAdd.disabled = "true";
    var selected = select.options.selectedIndex;
    
    addChartSeries(selected);
    
    buttonAdd.disabled = "";
},false);

buttonClear.addEventListener("click",function(e){
    buttonClear.disabled = "true";
    if (window.confirm("Do you want to clear?")) {
        var seriesLength = chart.series.length;
        for(var i = seriesLength - 1; i > -1; i--)
        {
            chart.series[i].remove();
            // if(chart.series[i].name ==document.getElementById("series_name").value)
            //     chart.series[i].remove();
        }
    }
    

    buttonClear.disabled = "";
},false);

buttonDrawAll.addEventListener("click",function(e){
    buttonClear.disabled = "true";

    for(var i = select.options.length - 1; i > -1; i--) {
        addChartSeries(select.options[i].getAttribute('value'));
    }

    buttonClear.disabled = "";
},false);

</script>
`;
    
}


http.createServer(function(request, response) {  
        response.writeHeader(200, {"Content-Type": "text/html"});  
  
        var url = request.url;
        var html = '';
        if((request.url).startsWith('/get') && request.method === 'GET'){
            
            const url = new URL(request.url, serverOrigin);
            // Parse the URL query. The leading '?' has to be removed before this.
            const query = parseQuery(url.search.substr(1));
            if (query.id) {
                // console.log(query);
                //console.log(seriesData);
                // console.log(seriesData[query.id]);
                // console.log(seriesData[parseInt(query.id)]);
                //console.log(query);
                html = JSON.stringify(seriesData[query.id] && Object.keys(seriesData[query.id]).length>0 ? seriesData[parseInt(query.id)] : []);
            } else {
                html = JSON.stringify([]);
            }
            // amounts_reserve1.push(parseFloat(query.amount_reserve1));
            // amounts_reserve2.push(parseFloat(query.amount_reserve2));
            // amounts_buy.push(parseFloat(query.amount_sell));
            // amounts_sell.push(parseFloat(query.amount_buy));
            // prices.push(parseFloat(query.price));
            // titles.push(typeof(query.title) ==="undefined" ? prices.length : query.title);
            
            // html = "true";

        // } else if((request.url).startsWith('/clear') && request.method === 'GET'){
        //     // amounts_buy = [];
        //     // amounts_sell = [];
        //     // prices = [];
        //     // titles = [];
        //     // amounts_reserve1 = [];
        //     // amounts_reserve2 = [];
        //     // html =""+
        //     // "<script>"+
        //     // "    window.location.href = '"+serverOrigin+"';"+
        //     // "</script>"+
        //     // "";
        // } else if((request.url).startsWith('/fastrefresh') && request.method === 'GET'){
        //     // if (refreshTimeSec == refreshTimeSecDefault) {
        //     //     refreshTimeSec=2000;
        //     // } else {
        //     //     refreshTimeSec=refreshTimeSecDefault;
        //     // }
        //     // html =""+
        //     // "<script>"+
        //     // "    window.location.href = '"+serverOrigin+"';"+
        //     // "</script>"+
        //     // "";
        // } else if((request.url).startsWith('/refresh') && request.method === 'GET'){
        //     html = `
        //     <script>
        //         window.location.href = '${serverOrigin}';
        //     </script>
        //     `;
        }else {
            html = generateHtml();
        }
        
        response.write(html);
        response.end();  
        
        
    
    }).listen(PORT);