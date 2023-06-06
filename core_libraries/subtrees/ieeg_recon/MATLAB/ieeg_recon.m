classdef ieeg_recon

    %ieeg_recon is the electrode coregistration pipeline
    %   Detailed explanation goes here

    properties
        preImplantMRI
        postImplantCT
        postImplantCT_electrodes
        output
        fslLoc
        itksnap
        freeSurfer
    end

    methods

        % Constructor
        function obj = ieeg_recon(sub, ct_ses, mri_ses, BIDS_dir)

            arguments
                sub 
                ct_ses
                mri_ses
                BIDS_dir
            end

            BIDS_dir = what(BIDS_dir).path;
            mri_prefix = fullfile(BIDS_dir, sub, mri_ses);
            ct_prefix = fullfile(BIDS_dir, sub, ct_ses);

            obj.preImplantMRI = fullfile(mri_prefix, 'anat', [sub '_' mri_ses '_acq-3D_space-T00mri_T1w.nii.gz']);
            obj.postImplantCT = fullfile(ct_prefix, 'ct', [sub '_' ct_ses '_acq-3D_space-T01ct_ct.nii.gz']);
            obj.postImplantCT_electrodes = fullfile(ct_prefix, 'ieeg', [sub '_' ct_ses '_space-T01ct_desc-vox_electrodes.txt']);
            obj.output = fullfile(BIDS_dir, sub, 'derivatives'); 

            % Check that files exist
            mustBeFile(obj.preImplantMRI)
            mustBeFile(obj.postImplantCT)
            mustBeFile(obj.postImplantCT_electrodes)

            obj.fslLoc = getenv('FSLDIR');
            obj.itksnap= getenv('ITKSNAPDIR');

            % Check that library paths exist
            if ~isfolder(obj.fslLoc)
                disp('FSLDIR environment variable not set')
            end

            if ~isfolder(obj.itksnap)
                disp('ITKSNAPDIR environment variable not set')
            end

        end

        function module1(obj)
            %module1: exports electrode coordinates of post implant CT in voxel and
            %native space. Outputs of this module goes in
            %output:ieeg_recon/module1 folder

            mkdir(fullfile(obj.output, 'ieeg_recon', 'module1'))

            % Export electrode cordinates in CT space in mm and vox
            elecCTvox = readtable(obj.postImplantCT_electrodes);
            writecell(elecCTvox{:, 1}, fullfile(obj.output, 'ieeg_recon', 'module1', 'electrode_names.txt'));
            writematrix(elecCTvox{:, 2:4}, fullfile(obj.output, 'ieeg_recon', 'module1', 'electrodes_inCTvox.txt'), 'Delimiter', 'space');

            CT.hdr = niftiinfo(obj.postImplantCT);
            CT.data = niftiread(obj.postImplantCT);

            threshold_to_removeSkull = 99.95; % percentile
            [CT.vox(:, 1), CT.vox(:, 2), CT.vox(:, 3)] = ind2sub(size(CT.data), ...
                find(CT.data > prctile(CT.data(:), threshold_to_removeSkull)));

            CT.mm = CT.hdr.Transform.T' * [CT.vox, ones(size(CT.vox, 1), 1)]';
            CT.mm = transpose(CT.mm);

            elecCTmm = transpose(CT.hdr.Transform.T' * [elecCTvox{:, 2:4}, ones(size(elecCTvox, 1), 1)]');
            writematrix(elecCTmm(:, 1:3), fullfile(obj.output, 'ieeg_recon', 'module1', 'electrodes_inCTmm.txt'), 'Delimiter', 'space')

        end

        function fileLocations = module2(obj, varargin)
            %module2: Outputs of this module goes in
            %output:ieeg_recon/module2 folder

            mkdir(fullfile(obj.output, 'ieeg_recon', 'module2'));

            try 
                
                assert(varargin{2});

                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRImm.txt'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRIvox.txt'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI.nii.gz'));
                mustBeFile(fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI_freesurferLUT.txt'));

                fileLocations.ct_to_mri = fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz');
                fileLocations.electrodes_inMRI = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI.nii.gz');
                fileLocations.electrodes_inMRI_freesurferLUT = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI_freesurferLUT.txt');
                fileLocations.electrodes_inMRImm = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRImm.txt');
                fileLocations.electrodes_inMRIvox = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRIvox.txt');

            catch

                % remove negative values from CT image
                cmd = sprintf('%s %s -thr 0 %s',...
                    fullfile(obj.fslLoc,'bin','fslmaths'), ...
                    obj.postImplantCT, ...
                    fullfile(obj.output, 'ieeg_recon', 'module2', 'ct_thresholded.nii.gz'));

                system(cmd, "-echo");

                % Greedy Image Centering: Apply greedy with image centering
                if matches(varargin{1}, 'gc')
                    
                    disp('Running greedy registration with image centering');
                    cmd = [fullfile(obj.itksnap, 'greedy') ...
                        ' -d 3' ...
                        ' -i ' obj.preImplantMRI ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat') ...
                        ' -a -dof 6' ...
                        ' -m NMI' ...
                        ' -ia-image-centers' ...
                        ' -n 100x100x0x0' ...
                        ' -jitter 0.9' ...
                        ' -search 1000 10 20' ...
                        ' >' fullfile(obj.output, 'ieeg_recon','module2','greedy.log')];

                    system(cmd, "-echo");

                    % Convert greedy transform centering to FSL format
                    cmd = [fullfile(obj.itksnap, 'c3d_affine_tool') ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -src ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat') ...
                        ' -ras2fsl' ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt')];

                    system(cmd, "-echo");
                    delete(fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat'));

                    % Apply greedy transform centering on ct_thresholded image
                    cmd = [fullfile(obj.fslLoc, 'flirt') ...
                        ' -in ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -init ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                        ' -out ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ...
                        ' -applyxfm'];

                    system(cmd, "-echo");

                elseif matches(varargin{1}, 'g')
                    
                    disp('Running FLIRT registration fine-tuned with greedy');
                    % FLIRT: Register CT to preimapnt T1 MRI
                    cmd = [fullfile(obj.fslLoc, 'flirt') ...
                        ' -cost mutualinfo' ...
                        ' -usesqform' ...
                        ' -dof 6' ...
                        ' -bins 640' ...
                        ' -v' ...
                        ' -searchrx -180 180 -searchry -180 180 -searchrz -180 180' ...
                        ' -in ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -out ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_flirt.nii.gz') ...
                        ' -omat ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_flirt.txt') ...
                        ' >' fullfile(obj.output, 'ieeg_recon','module2','flirt.log')];

                    system(cmd, "-echo");

                    % Greedy: Fine-tune flirt registered ct_to_mri to preimapnt T1 MRI
                    cmd = [fullfile(obj.itksnap , 'greedy') ...
                        ' -d 3' ...
                        ' -i ' obj.preImplantMRI ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_flirt.nii.gz') ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_greedy.mat') ...
                        ' -a -dof 6' ...
                        ' -m NMI' ...
                        ' -ia-identity' ...
                        ' -n 100x100x100x0' ...
                        ' -jitter 0.9' ...
                        ' -search 1000 10 20' ...
                        ' >' fullfile(obj.output, 'ieeg_recon','module2','greedy.log')];

                    system(cmd, "-echo");

                    % Convert greedy transform to FSL format
                    cmd = [obj.itksnap , 'c3d_affine_tool' ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -src ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_flirt.nii.gz') ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_greedy.mat') ...
                        ' -ras2fsl' ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_greedy.txt')];

                    system(cmd, "-echo");
                    delete(fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_greedy.mat'));

                    % Concatenate greedy and flirt transforms
                    cmd = [fullfile(obj.fslLoc , 'convert_xfm') ...
                        ' -omat ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                        ' -concat' ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_greedy.txt') ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_flirt.txt')];

                    system(cmd, "-echo");
  
                    % Apply combined registration to CT
                    % replace flirt ct_to_mri with new ct_to_mri
                    cmd = [obj.fslLoc , 'flirt' ...
                        ' -in ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -init ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                        ' -out ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ...
                        ' -applyxfm'];

                    system(cmd, "-echo");

                elseif matches(varargin{1}, 'gc_noCTthereshold')
                    
                    disp('Running greedy registration with image centering');
                    cmd = [fullfile(obj.itksnap , 'greedy') ...
                        ' -d 3' ...
                        ' -i ' obj.preImplantMRI ...
                        ' ' obj.postImplantCT ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat') ...
                        ' -a -dof 6' ...
                        ' -m MI' ...
                        ' -ia-image-centers' ...
                        ' -n 100x50x0x0' ...
                        ' >' fullfile(obj.output, 'ieeg_recon','module2','greedy.log')];

                    system(cmd, "-echo");

                    % Convert greedy transform centering to FSL format
                    cmd = [obj.itksnap , 'c3d_affine_tool' ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -src ' obj.postImplantCT ...
                        ' ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat') ...
                        ' -ras2fsl' ...
                        ' -o ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt')];

                    system(cmd, "-echo");
                    delete(fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.mat'));

                    % Apply greedy transform centering on ct_thresholded image
                    cmd = [fullfile(obj.fslLoc , 'flirt') ...
                        ' -in ' obj.postImplantCT ...
                        ' -ref ' obj.preImplantMRI ...
                        ' -init ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                        ' -out ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ...
                        ' -applyxfm'];

                    system(cmd, "-echo");

                    % remove negative values from CT image
                    cmd = [obj.fslLoc , 'fslmaths ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ' -thr 0 ' ...
                        fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz')];

                    system(cmd, "-echo");

                else

                    error("Input missing, registration: Greedy with centering: 'gc', 'gc_noCTthereshold', or FLIRT with greedy: 'g'")

                end

                % Apply registration to electrode coordinates both in mm and vox
                cmd = [fullfile(obj.fslLoc , 'img2imgcoord') ...
                    ' -src ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                    ' -dest ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ...
                    ' -xfm ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                    ' -mm ' fullfile(obj.output, 'ieeg_recon','module1','electrodes_inCTmm.txt') ...
                    ' > ' fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRImm.txt')];

                system(cmd, "-echo")

                cmd = [fullfile(obj.fslLoc , 'img2imgcoord') ...
                    ' -src ' fullfile(obj.output, 'ieeg_recon','module2','ct_thresholded.nii.gz') ...
                    ' -dest ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz') ...
                    ' -xfm ' fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri_xform.txt') ...
                    ' -vox ' fullfile(obj.output, 'ieeg_recon','module1','electrodes_inCTvox.txt') ...
                    ' > ' fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRIvox.txt')];

                system(cmd, "-echo");

                % Draw sphere of 2mm radius with electrode cordinate in
                % the center in the registered CT space

                % Create a blank nifti file in the space of registered ct_to_mri.nii.gz
                hdr = niftiinfo([obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz']);
                data =  niftiread([obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz']);
                data(data~=0) = 0;
                [dataVox(:,1), dataVox(:,2), dataVox(:,3)] = ind2sub(size(data), find(data==0));
                datamm = hdr.Transform.T' * [dataVox, ones(size(dataVox, 1), 1)]';
                datamm = transpose(datamm);
                datamm(:,4) = [];

                % Load electrode coordinates in mm
                electrodes_mm = importdata([obj.output 'ieeg_recon','module2','electrodes_inMRImm.txt']);
                electrodes_mm = electrodes_mm.data;

                % Export electrode labels for freesurfer
                electrode_freesurferLUT.index = transpose(1:size(electrodes_mm,1));
                electrode_freesurferLUT.names = importdata([obj.output 'ieeg_recon','module1','electrode_names.txt']);
                electrode_freesurferLUT.R = repmat(90, size(electrodes_mm,1),1);
                electrode_freesurferLUT.G = repmat(150, size(electrodes_mm,1),1);
                electrode_freesurferLUT.B = repmat(60, size(electrodes_mm,1),1);
                electrode_freesurferLUT.alpha = zeros(size(electrodes_mm,1),1);
                electrode_freesurferLUT = struct2table(electrode_freesurferLUT);
                writetable(electrode_freesurferLUT, [obj.output 'ieeg_recon','module2','electrodes_inMRI_freesurferLUT.txt'], ...
                    'Delimiter','space', 'WriteVariableNames', false);

                % Assign point for each electrode with a unique value
                [idx, dist_mm] = knnsearch(electrodes_mm,datamm);

                % only keep dist_mm <= 2 mm
                electrodesData = [find(dist_mm <= 2), idx(dist_mm <= 2), dist_mm(dist_mm <= 2)];
                [electrodesData(:,4), electrodesData(:,5), electrodesData(:,6)] = ind2sub(size(data), electrodesData(:,1));

                for n = 1:size(electrodesData,1)
                    data(electrodesData(n,4), electrodesData(n,5), electrodesData(n,6)) = electrodesData(n,2);
                end

                electrode_map = [obj.output 'ieeg_recon','module2','electrodes_inMRI.nii'];
                niftiwrite(data, electrode_map ,hdr, 'Compressed',true);

                fileLocations.ct_to_mri = fullfile(obj.output, 'ieeg_recon','module2','ct_to_mri.nii.gz');
                fileLocations.electrodes_inMRI = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI.nii.gz');
                fileLocations.electrodes_inMRI_freesurferLUT = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRI_freesurferLUT.txt');
                fileLocations.electrodes_inMRImm = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRImm.txt');
                fileLocations.electrodes_inMRIvox = fullfile(obj.output, 'ieeg_recon','module2','electrodes_inMRIvox.txt');
            end            
        end

        function module2_QualityAssurance(obj,fileLocations,imageviewer)

            mkdir(fullfile(obj.output, 'ieeg_recon','module2'));

            if matches(imageviewer, 'freeview_snapshot')

                cmd = [fullfile(obj.freeSurfer, 'freeview') ...
                    ' -v ' obj.preImplantMRI ...
                    ' ' fileLocations.ct_to_mri ':colormap=heat' ...
                    ' ' fileLocations.electrodes_inMRI...
                    ':colormap=lut:lut=' fileLocations.electrodes_inMRI_freesurferLUT...
                    ' -viewport sagittal' ...
                    ' -ss ' fullfile(obj.output, 'ieeg_recon','module2','QA_registation_sagittal.png')];
                system(cmd, "-echo");

                cmd = [fullfile(obj.freeSurfer , 'freeview') ...
                    ' -v ' obj.preImplantMRI ...
                    ' ' fileLocations.ct_to_mri ':colormap=heat' ...
                    ' ' fileLocations.electrodes_inMRI...
                    ':colormap=lut:lut=' fileLocations.electrodes_inMRI_freesurferLUT...
                    ' -viewport coronal' ...
                    ' -ss ' fullfile(obj.output, 'ieeg_recon','module2','QA_registation_coronal.png')];
                system(cmd, "-echo");

                cmd = [fullfile(obj.freeSurfer , 'freeview') ...
                    ' -v ' obj.preImplantMRI ...
                    ' ' fileLocations.ct_to_mri ':colormap=heat' ...
                    ' ' fileLocations.electrodes_inMRI...
                    ':colormap=lut:lut=' fileLocations.electrodes_inMRI_freesurferLUT...
                    ' -viewport axial'...
                    ' -ss ' fullfile(obj.output, 'ieeg_recon','module2','QA_registation_axial.png')];
                system(cmd, "-echo");

                cmd = [obj.freeSurfer , 'freeview' ...
                    ' -v ' fileLocations.ct_to_mri ':colormap=heat' ...
                    ' ' fileLocations.electrodes_inMRI...
                    ':colormap=lut:lut=' fileLocations.electrodes_inMRI_freesurferLUT ':isosurface=on'...
                    ' -viewport 3d -view anterior'...
                    ' -ss ' fullfile(obj.output, 'ieeg_recon','module2','QA_registation_3D.png')];
                system(cmd, "-echo");

            elseif matches(imageviewer, 'freeview')

                cmd = [fullfile(obj.freeSurfer , 'freeview') ...
                    ' -v ' obj.preImplantMRI ...
                    ' ' fileLocations.ct_to_mri ':colormap=heat' ...
                    ' ' fileLocations.electrodes_inMRI...
                    ':colormap=lut:lut=' fileLocations.electrodes_inMRI_freesurferLUT...
                    ' -viewport sagittal'];
                system(cmd, "-echo");

            elseif matches(imageviewer, 'itksnap')

                cmd = [obj.itksnap , 'itksnap' ...
                    ' -g ' obj.preImplantMRI ...
                    ' -o ' fileLocations.ct_to_mri];
                system(cmd, "-echo");

            else

                 error("Imageviewer missing. Specify: 'itksnap', 'freeview', or 'freeview_snapshot' ")

            end

        end

        function electrodes2ROI = module3(obj, atlas, lookupTable)
            %module3: Outputs of this module goes in
            %output:ieeg_recon/module3 folder

            mkdir(fullfile(obj.output, 'ieeg_recon','module3'));

            mustBeFile(atlas);
            mustBeFile(lookupTable);

            %% Load electrode coordinates in mm, and read atlas in native space from nifti file

            electrodes_mm = importdata([obj.output 'ieeg_recon','module2','electrodes_inMRImm.txt']);
            electrodes_mm = electrodes_mm.data;

            electrodes_vox = importdata([obj.output 'ieeg_recon','module2','electrodes_inMRIvox.txt']);
            electrodes_vox = electrodes_vox.data;

            labels = importdata([obj.output 'ieeg_recon','module1','electrode_names.txt']);

            hdr = niftiinfo(atlas);
            data = niftiread(atlas);
            lut = readtable(lookupTable);

            %% Atlas roi in voxels
            atlas_voxels = [];

            for r = 1:size(lut, 1)

                [vox(:, 1), vox(:, 2), vox(:, 3)] = ind2sub(size(data), find(data == lut.roiNum(r)));
                vox(:, 4) = repmat(lut.roiNum(r), size(vox, 1), 1);
                atlas_voxels = [atlas_voxels; vox];
                clear vox

            end

            %% Atlas roi in mm
            cord_mm = hdr.Transform.T' * [atlas_voxels(:, 1:3), ones(size(atlas_voxels, 1), 1)]';
            cord_mm = transpose(cord_mm);
            cord_mm = [cord_mm(:, 1:3), atlas_voxels(:, 4)];

            %% Map electrode contacts to all ROI

            [idx, dist_mm] = knnsearch(cord_mm(:, 1:3), electrodes_mm, 'K', 1);
            implant2roiNum = cord_mm(idx, 4);
            [~, idx] = ismember(implant2roiNum, lut.roiNum);
            implant2roi = lut.roi(idx);

            % if an electrode is not within 2.5mm of any ROI it is in the white matter
            % or outside the brain
            implant2roiNum(dist_mm >= 2.6) = nan;
            [implant2roi{dist_mm >= 2.6, :}] = deal('');

            electrodes2ROI = table(labels, ...
                electrodes_mm(:, 1), electrodes_mm(:, 2), electrodes_mm(:, 3), ...
                electrodes_vox(:, 1), electrodes_vox(:, 2), electrodes_vox(:, 3), ...
                implant2roi, implant2roiNum);

            electrodes2ROI.Properties.VariableNames(2) = "mm_x";
            electrodes2ROI.Properties.VariableNames(3) = "mm_y";
            electrodes2ROI.Properties.VariableNames(4) = "mm_z";
            electrodes2ROI.Properties.VariableNames(5) = "vox_x";
            electrodes2ROI.Properties.VariableNames(6) = "vox_y";
            electrodes2ROI.Properties.VariableNames(7) = "vox_z";
            electrodes2ROI.Properties.VariableNames(8) = "roi";
            electrodes2ROI.Properties.VariableNames(9) = "roiNum";

            writetable(electrodes2ROI, fullfile(obj.output, 'ieeg_recon','module3','electrodes2ROI.csv'))

        end

    end

end
