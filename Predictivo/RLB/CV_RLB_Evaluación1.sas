PROC IMPORT DATAFILE="D:\UCM\Curso 4\Resultados\Predictivo\Base_Final_Predictivo.xlsx"
    OUT=datos_tfg
    DBMS=XLSX
    REPLACE;
    GETNAMES=YES;
RUN;

PROC PRINT DATA=datos_tfg (OBS=10);
RUN;


* 1. CREAR VARIABLE DEPENDIENTE;
DATA datos_tfg;
    SET datos_tfg;

    IF Est_Salud = "Malo" THEN Salud_bin = 1;
    ELSE IF Est_Salud = "Bueno" THEN Salud_bin = 0;
RUN;


* 2. PARTICIÓN TRAIN;
proc surveyselect data=datos_tfg
    out=particion
    samprate=0.8
    seed=12345
    outall;
run;

data train test;
    set particion;

    if Selected=1 then output train;
    else output test;
run;

* VALIDACIÓN CRUZADA (k=5);
   * PASO 0. ASIGNAR FOLD A CADA OBSERVACIÓN DE TRAIN;
proc surveyselect data=train
    out=train_cv
    method=srs
    samprate=1
    seed=12345
    outall;
run;

data train_cv;
    set train_cv;
    fold = mod(_n_, 5) + 1;
run;


* PASO 1. TABLA VACÍA PARA GUARDAR RESULTADOS;
data resultados_cv;
    length modelo $40;
    length fold AUC Accuracy Sensibilidad Especificidad 8;
    stop;
run;


* PASO 2. MACRO DE VALIDACIÓN CRUZADA;
%macro cv_logistica(modelo=, vars=, selection=none, slentry=, slstay=);

    %do f = 1 %to 5;

        * Partición  del fold;
        data cv_train cv_val;
            set train_cv;
            if fold = &f then output cv_val;
            else output cv_train;
        run;

        * Entrenar modelo en cv_train;
        %if &selection = none %then %do;
            proc logistic data=cv_train;
                model Salud_bin(event='1') = &vars;
                score data=cv_val out=score_val_&f;
            run;
        %end;
        %else %if &slentry ne and &slstay ne %then %do;
            proc logistic data=cv_train ;
                model Salud_bin(event='1') = &vars
                    / selection=&selection slentry=&slentry slstay=&slstay;
                score data=cv_val out=score_val_&f;
            run;
        %end;
        %else %if &slentry ne %then %do;
            proc logistic data=cv_train ;
                model Salud_bin(event='1') = &vars
                    / selection=&selection slentry=&slentry;
                score data=cv_val out=score_val_&f;
            run;
        %end;
        %else %do;
            proc logistic data=cv_train ;
                model Salud_bin(event='1') = &vars
                    / selection=&selection slstay=&slstay;
                score data=cv_val out=score_val_&f;
            run;
        %end;

        * Clasificar con cutoff fijo 0.5;
        data score_val_&f;
            set score_val_&f;
            phat = P_1;
            pred = (phat >= 0.5);
        run;

        * AUC en validación (Wilcoxon);
        proc sql noprint;
            select mean(case
                        when a.phat > b.phat then 1
                        when a.phat = b.phat then 0.5
                        else 0 end)
            into :auc_f trimmed
            from score_val_&f a, score_val_&f b
            where a.Salud_bin = 1 and b.Salud_bin = 0;
        quit;

        * Métricas de clasificación;
        proc sql noprint;
            select sum(case when Salud_bin=pred then 1 else 0 end) / count(*)
            into :acc_f trimmed
            from score_val_&f;

            select sum(case when Salud_bin=1 and pred=1 then 1 else 0 end) /
                   sum(case when Salud_bin=1 then 1 else 0 end)
            into :se_f trimmed
            from score_val_&f;

            select sum(case when Salud_bin=0 and pred=0 then 1 else 0 end) /
                   sum(case when Salud_bin=0 then 1 else 0 end)
            into :sp_f trimmed
            from score_val_&f;
        quit;

        * Guardar resultados del fold;
        data fold_res;
            length modelo $40;
            modelo        = "&modelo";
            fold          = &f;
            AUC           = &auc_f;
            Accuracy      = &acc_f;
            Sensibilidad  = &se_f;
            Especificidad = &sp_f;
        run;

        proc append base=resultados_cv data=fold_res force;
        run;

    %end;

%mend cv_logistica;


* PASO 3. EJECUTAR LOS 7 MODELOS;

%let vars = Comp1 Comp2 Comp3 Comp4 Comp5 Comp6 Comp7 Edad;

* Modelo 0: Completo;
%cv_logistica(modelo=Completo,
              vars=&vars,
              selection=none);

* Modelo 1: Stepwise a=0.05;
%cv_logistica(modelo=Stepwise_005,
              vars=&vars,
              selection=stepwise,
              slentry=0.05,
              slstay=0.05);

* Modelo 2: Forward a=0.05;
%cv_logistica(modelo=Forward_005,
              vars=&vars,
              selection=forward,
              slentry=0.05);

* Modelo 3: Backward a=0.05;
%cv_logistica(modelo=Backward_005,
              vars=&vars,
              selection=backward,
              slstay=0.05);

* Modelo 4: Stepwise a=0.01;
%cv_logistica(modelo=Stepwise_001,
              vars=&vars,
              selection=stepwise,
              slentry=0.01,
              slstay=0.01);

* Modelo 5: Forward a=0.01;
%cv_logistica(modelo=Forward_001,
              vars=&vars,
              selection=forward,
              slentry=0.01);

* Modelo 6: Backward a=0.01;
%cv_logistica(modelo=Backward_001,
              vars=&vars,
              selection=backward,
              slstay=0.01);


* PASO 4. TABLA RESUMEN (media y desv.típica por modelo);
proc means data=resultados_cv mean std min max;
    class modelo;
    var AUC Accuracy Sensibilidad Especificidad;
    title "Resumen CV k=5";
run;


* PASO 5. BOXPLOTS COMPARATIVOS;
* AUC;
proc sgplot data=resultados_cv;
    vbox AUC / category=modelo fillattrs=(transparency=0.3)
               lineattrs=(thickness=1.5);
    xaxis label="Modelo" fitpolicy=rotate;
    yaxis label="AUC" min=0.5 max=1;
    title "Validación Cruzada k=5 AUC";
run;

* Accuracy;
proc sgplot data=resultados_cv;
    vbox Accuracy / category=modelo fillattrs=(transparency=0.3)
                    lineattrs=(thickness=1.5);
    xaxis label="Modelo" fitpolicy=rotate;
    yaxis label="Accuracy" min=0.5 max=1;
    title "Validación Cruzada k=5 Accuracy";
run;

* Sensibilidad;
proc sgplot data=resultados_cv;
    vbox Sensibilidad / category=modelo fillattrs=(transparency=0.3)
                        lineattrs=(thickness=1.5);
    xaxis label="Modelo" fitpolicy=rotate;
    yaxis label="Sensibilidad" min=0 max=1;
    title "Validación Cruzada k=5 Sensibilidad";
run;

* Especificidad;
proc sgplot data=resultados_cv;
    vbox Especificidad / category=modelo fillattrs=(transparency=0.3)
                         lineattrs=(thickness=1.5);
    xaxis label="Modelo" fitpolicy=rotate;
    yaxis label="Especificidad" min=0 max=1;
    title "Validación Cruzada k=5 Especificidad";
run;
