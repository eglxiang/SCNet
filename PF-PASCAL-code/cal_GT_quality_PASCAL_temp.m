%check dense warp using keypoints in reference and target images
%evaluate PCK for one KP randomly selected, with dense corres.
%automatically generated other KPs using TPS warping
% written by Bumsub Ham, Inria - WILLOW
close all;
clear all;

% ===========================================
% set parameters
% ===========================================

showKP = false;
PCK_thresh = 0.10; % PCK threshold (alpha)
num_try=10;

% ===========================================
% set config
% ===========================================

% parameter for tps warping
interp.method = 'invdist'; %'nearest'; %'none' % interpolation method
interp.radius = 5; % radius or median filter dimension
interp.power = 2; %power for inverse wwighting interpolation method

% add path
addpath('../tpsWarp/');
addpath('../commonFunctions');

global conf;

% dataset
conf.datasetDir = '../PF-dataset-PASCAL/';

% keypoint
conf.annoKPDir = [conf.datasetDir 'Annotations/'];
conf.imageDir = [conf.datasetDir 'JPEGImages/'];

% object classes
conf.class = dir(conf.annoKPDir) ;
conf.class = {conf.class(4:end).name};

conf.benchmarkDir = '../_GTCheck-PASCAL/';
% conf.resDir = fullfile(conf.benchmarkDir, '_res_try(2)');
% if isempty(dir(conf.resDir))
%     mkdir(conf.resDir);
% end

colorCode = makeColorCode(100);

% ======================================================
% Compute Max, Min, Avg of KPs
% ======================================================
statKP = struct([]);
fprintf('Parsing keypoints statistics...done.\n');
for ci = 1:length(conf.class)
    
    % load the annotation file
    load(fullfile(conf.benchmarkDir,sprintf('KP_%s.mat',conf.class{ci})), 'KP');
    
    KP_per_class = sum(KP.part_visible);
    
    statKP(ci).class = conf.class{ci};
    statKP(ci).min = min(KP_per_class);
    statKP(ci).max = max(KP_per_class);
    statKP(ci).avg = mean(KP_per_class);
end
num_leave = max([statKP.max])-3;

% ======================================================
% PCK with leave-n-out test (# of leave = from 1 to maximum number of KPs - 3)
% leave KPs are randomly selected.
% ======================================================
PCK_per_num_leave = zeros(num_leave, 1);

GTcheck = struct([]);
GTcheck(1).alpha = PCK_thresh;

% load matching pair
load(fullfile(conf.datasetDir,'parsePascalVOC.mat'), 'PascalVOC');

for tr = 2:num_try
    
    conf.resDir = fullfile(conf.benchmarkDir, sprintf('_res_try(%d)', tr));
    if isempty(dir(conf.resDir))
        mkdir(conf.resDir);
    end
    
    for li = 1:num_leave
        
        GTcheck(1).avgPCK=0;
        
        valid_class = 0;
        
        for ci = 1:length(conf.class)
            
            fprintf('Class: %s...\n',conf.class{ci});
            
            % load the annotation file
            load(fullfile(conf.benchmarkDir,sprintf('KP_%s.mat',conf.class{ci})), 'KP');
            
            % set matching pair
            classInd = pascalClassIndex(conf.class{ci});
            pair = PascalVOC.pair{classInd};
            
            GTcheck(ci).class = conf.class{ci};
            GTcheck(ci).PCK=0;
            
            % compute dense warp using keypoints
            valid_cnt = 0;
            for fi=1:length(pair)
                
                if mod(fi,10) == 0
                    fprintf('%03d/%03d\n', fi,length(pair));
                end
                
                % =========================================================================
                % configuration for image A
                % =========================================================================
                imgA_name = cell2mat(strcat(pair(fi,1)));
                imgA=imread(fullfile(conf.imageDir,[imgA_name '.jpg']));
                imgA_height=size(imgA,1);imgA_width=size(imgA,2);
                imgA_idx = find(strcmp(KP.image_name,[imgA_name '.jpg']));
                
                annoA = KP.image2anno{imgA_idx};
                part_x_A = KP.part_x(:,annoA);
                part_y_A = KP.part_y(:,annoA);
                % delete invisible parts
                part_x_A = part_x_A(~isnan(part_x_A));
                part_y_A = part_y_A(~isnan(part_y_A));
                
                % =========================================================================
                % configuration for image B
                % =========================================================================
                imgB_name = cell2mat(strcat(pair(fi,2)));
                imgB=imread(fullfile(conf.imageDir,[imgB_name '.jpg']));
                imgB_height=size(imgB,1);imgB_width=size(imgB,2);
                imgB_idx = find(strcmp(KP.image_name,[imgB_name '.jpg']));
                
                annoB = KP.image2anno{imgB_idx};
                part_x_B = KP.part_x(:,annoB);
                part_y_B = KP.part_y(:,annoB);
                % delete invisible parts
                part_x_B = part_x_B(~isnan(part_x_B));
                part_y_B = part_y_B(~isnan(part_y_B));
                
                if length(part_x_A) - 3 < li
                    continue;
                else
                    % select random keypoint among predefined ones
                    random_KP=randperm(length(part_x_A), li);
                    
                    % test keypoint for ref image
                    GT_KP_x_A=part_x_A(random_KP);
                    GT_KP_y_A=part_y_A(random_KP);
                    part_x_A(random_KP) = [];
                    part_y_A(random_KP) = [];
                    
                    xy_idx =  sub2ind([imgA_width,imgA_height],round(GT_KP_x_A),round(GT_KP_y_A));
                    
                    % test keypoint for tar image
                    GT_KP_x_B=part_x_B(random_KP);
                    GT_KP_y_B=part_y_B(random_KP);
                    part_x_B(random_KP) = [];
                    part_y_B(random_KP) = [];
                    
                    [warped_coord_y, warped_coord_x, imgW, imgWr]  = ...
                        tpswarp(imgA,[size(imgB,2) size(imgB,1)],[double(part_y_A) double(part_x_A)],[double(part_y_B) double(part_x_B)],interp); % thin plate spline warping
                    imgW = uint8(imgW);
                    imgWr = uint8(imgWr);
                    
                    warped_coord_x = round(warped_coord_x);
                    warped_coord_y = round(warped_coord_y);
                    
                    % Bound warped coordinates to image frame
                    warped_coord_x = max(min(warped_coord_x,imgB_width),1);
                    warped_coord_y = max(min(warped_coord_y,imgB_height),1);
                    
                    % warped test keypoint using estimated dense field
                    warped_GT_KP_x_A = warped_coord_x(xy_idx);
                    warped_GT_KP_y_A = warped_coord_y(xy_idx);
                    
                    %evaluate PCK
                    error = sqrt((warped_GT_KP_x_A - GT_KP_x_B).^2 + (warped_GT_KP_y_A - GT_KP_y_B).^2);
                    correct = error <= PCK_thresh * max([imgB_width, imgB_height]);
                    
                    GTcheck(ci).PCK = GTcheck(ci).PCK+sum(correct)/li;
                    valid_cnt = valid_cnt+1;
                    
                    % ======================================================
                    % Show keypoints
                    % ======================================================
                    if showKP
                        % show warped image
                        warpout = appendimages(imgWr,imgW);
                        clf(figure(1),'reset')
                        figure(1);
                        imshow(warpout);hold on;
                        
                        %plot keypoints
                        imout = appendimages(imgA,imgB);
                        clf(figure(2),'reset')
                        figure(2);
                        imshow(rgb2gray(imout)); hold on;
                        
                        for kp=1:length(part_x_A)
                            plot(part_x_A(kp), part_y_A(kp),'o','MarkerEdgeColor','k',...
                                'MarkerFaceColor',colorCode(:,kp),'MarkerSize', 10);
                            plot(part_x_B(kp)+size(imgA,2),part_y_B(kp),'o','MarkerEdgeColor','k',...
                                'MarkerFaceColor',colorCode(:,kp),'MarkerSize', 10);
                        end
                        
                        for kp = 1:li
                            % show test KP for ref image (square)
                            plot(GT_KP_x_A(kp),GT_KP_y_A(kp),'s','MarkerEdgeColor','k',...
                                'MarkerFaceColor',colorCode(:,kp+length(part_x_A)),'MarkerSize', 15);
                            
                            % show test KP for tar image (square)
                            plot(GT_KP_x_B(kp)+size(imgA,2),GT_KP_y_B(kp),'s','MarkerEdgeColor','k',...
                                'MarkerFaceColor',colorCode(:,kp+length(part_x_A)),'MarkerSize', 15);
                            
                            % show estimated KP using dense corresopndence (diamond)
                            plot(warped_GT_KP_x_A(kp)+size(imgA,2),warped_GT_KP_y_A(kp),'d','MarkerEdgeColor','k',...
                                'MarkerFaceColor',colorCode(:,kp+length(part_x_A)),'MarkerSize', 15);
                        end
                        pause;
                    end
                    
                end
            end
            
            if valid_cnt == 0
                continue;
            else
                GTcheck(ci).PCK = GTcheck(ci).PCK/valid_cnt;
                GTcheck(1).avgPCK = GTcheck(1).avgPCK + GTcheck(ci).PCK;
                valid_class = valid_class+1;
            end
            
            fprintf('\n   =====================================================\n');
            fprintf('   Class: %s\n',conf.class{ci});
            fprintf('   PCK (alpha = %.2f) - (%d) points leave: %.2f\n', PCK_thresh, li, GTcheck(ci).PCK);
            fprintf('   =====================================================\n\n');
        end
        
        if valid_class == 0
            continue;
        else
            GTcheck(1).avgPCK = GTcheck(1).avgPCK / valid_class;
            fprintf('   \n* Mean PCK (alpha = %.2f) for all classes - (%d) points leave: %.2f \n\n', PCK_thresh, li, GTcheck(1).avgPCK);
            
            save(fullfile(conf.resDir, sprintf('PCK_alpha(%.2f)_leave(%d).mat',PCK_thresh,li)), 'GTcheck');
            
            PCK_per_num_leave(li) = GTcheck(1).avgPCK;
        end
    end
    save(fullfile(conf.resDir, sprintf('_PCK_alpha(%.2f).mat',PCK_thresh)), 'PCK_per_num_leave');
    save(fullfile(conf.resDir, '_KP_stat.mat'), 'statKP');
end
